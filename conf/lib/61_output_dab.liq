# DAB+ output configuration
# Uses ODR-AudioEnc for DAB+ encoding with EDI output

if
  DAB_ACK_WARN_SECONDS < 0
  or DAB_ACK_DOWN_SECONDS <= DAB_ACK_WARN_SECONDS
  or DAB_ACK_STARTUP_GRACE_SECONDS < 0
then
  failwith(
    "Invalid DAB ACK thresholds: require 0 <= warning < down and startup grace \
     >= 0"
  )
end

# Two-line status snapshot: first line is the state, the rest is detail.
let dab_ack_status =
  ref(
    "disabled\nDAB+ output is disabled"
  )

def dab_ack_snapshot_state(snapshot) =
  list.hd(default="down", r/\r?\n/.split(snapshot))
end

def dab_set_ack_status(snapshot) =
  let snapshot = string.trim(snapshot)
  let snapshot =
    if
      snapshot == ""
    then
      "down\nTCP ACK monitor returned no status"
    else
      snapshot
    end
  let previous_state = dab_ack_snapshot_state(dab_ack_status())
  let next_state = dab_ack_snapshot_state(snapshot)

  if
    next_state != previous_state
  then
    let log_level = if next_state == "ok" then 3 else 2 end
    log(
      label="dab",
      "TCP ACK monitor: #{previous_state} -> #{next_state}",
      level=log_level
    )
  end

  dab_ack_status := snapshot
end

# The monitor identifies AudioEnc's EDI sockets in ss output by process
# name; a dead encoder is reported by the reopen_on_error handler below.
let dab_ack_monitor_command =
  "/usr/local/bin/dab-tcp-ack-monitor --destinations #{
    process.quote(DAB_EDI_DESTINATIONS)
  } --ack-warn-seconds #{DAB_ACK_WARN_SECONDS} --ack-down-seconds #{
    DAB_ACK_DOWN_SECONDS
  } --startup-grace-seconds #{DAB_ACK_STARTUP_GRACE_SECONDS}"

def dab_ack_monitor_tick() =
  try
    let snapshot =
      process.read(timeout=5.0, log_errors=false, dab_ack_monitor_command)
    dab_set_ack_status(snapshot)
  catch err do
    dab_set_ack_status(
      "down\nTCP ACK monitor error: #{err.kind}: #{err.message}"
    )
  end
end

# Create DAB+ output stream
# Requires both DAB_BITRATE and DAB_EDI_DESTINATIONS to be configured
def output_dab_stream(audio_source) =
  if
    DAB_BITRATE != "" and DAB_EDI_DESTINATIONS != ""
  then
    log(
      "DAB+ output enabled - Bitrate: #{DAB_BITRATE}kbps, EDI: #{
        DAB_EDI_DESTINATIONS
      }",
      level=3
    )

    # Buffer provides clock isolation
    let audio_to_dab = mksafe(buffer(audio_source))

    let odr_command =
      ref(
        "/bin/odr-audioenc -i - --bitrate=#{process.quote(DAB_BITRATE)} --sbr"
      )

    # Add PAD configuration if socket is set
    if
      DAB_METADATA_SOCKET != ""
    then
      let pad_size =
        if DAB_METADATA_SIZE != "" then DAB_METADATA_SIZE else "8" end
      odr_command :=
        "#{odr_command()} --pad=#{process.quote(pad_size)} --pad-socket=#{
          process.quote(DAB_METADATA_SOCKET)
        }"
    end

    # Add EDI outputs - supports comma-separated list
    let edi_urls = string.split(separator=",", DAB_EDI_DESTINATIONS)
    list.iter(
      fun (edi_url) ->
        begin
          let trimmed_url = string.trim(edi_url)
          odr_command :=
            "#{odr_command()} --edi=#{process.quote(trimmed_url)}"
        end,
      edi_urls
    )

    if
      DAB_ACK_MONITOR_ENABLED
    then
      dab_set_ack_status(
        "starting\nWaiting for AudioEnc TCP acknowledgements"
      )
      thread.run(
        fast=false,
        delay=1.0,
        every=max(0.25, DAB_ACK_POLL_SECONDS),
        dab_ack_monitor_tick
      )
    else
      dab_set_ack_status(
        "unmonitored\nTCP ACK monitoring is disabled"
      )
    end

    # Feed audio to ODR-AudioEnc. Without reopen_on_error a dead encoder
    # raises a fatal clock error that stops the whole process; returning a
    # delay respawns the encoder instead and leaves other outputs untouched.
    ignore(
      output.external(
        %wav(channels = 2, samplerate = 48000),
        reopen_on_error=fun (err) ->
          begin
            dab_set_ack_status(
              "down\nDAB+ encoder error: #{err}"
            )
            log(
              "DAB+ encoder error: #{err} - restarting ODR-AudioEnc in 5s",
              level=2
            )
            5.0
          end,
        odr_command(),
        audio_to_dab
      )
    )
  else
    log(
      "DAB+ output disabled - DAB_BITRATE and/or DAB_EDI_DESTINATIONS not \
       configured",
      level=3
    )
  end

  server.register(
    description="Show DAB+ TCP acknowledgement health",
    "dab.status",
    fun (_) -> dab_ack_status()
  )
end

# DAB+ output configuration
# Uses ODR-AudioEnc for DAB+ encoding with EDI output

if
  DAB_ACK_POLL_SECONDS <= 0.0
then
  failwith(
    "Invalid DAB ACK poll interval: require a value greater than 0"
  )
end

if
  DAB_ACK_WARN_SECONDS < 0
or
  DAB_ACK_DOWN_SECONDS <= DAB_ACK_WARN_SECONDS
or
  DAB_ACK_STARTUP_GRACE_SECONDS < 0
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
  let (state, _) = string.split.first(separator="\n", snapshot)
  string.trim(state)
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
    let log_level =
      if
        list.mem(next_state, ["ok", "starting", "unmonitored", "disabled"])
      then
        3
      else
        2
      end
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
  process.quote.command(
    "/usr/local/bin/dab-tcp-ack-monitor",
    args=
      [
        "--destinations",
        DAB_EDI_DESTINATIONS,
        "--ack-warn-seconds",
        "#{DAB_ACK_WARN_SECONDS}",
        "--ack-down-seconds",
        "#{DAB_ACK_DOWN_SECONDS}",
        "--startup-grace-seconds",
        "#{DAB_ACK_STARTUP_GRACE_SECONDS}"
      ]
  )

def dab_edi_args(destinations) =
  let destinations =
    list.map(
      fun (destination) -> string.trim(destination),
      string.split(separator=",", destinations)
    )
  if
    list.exists(fun (destination) -> destination == "", destinations)
  then
    failwith(
      "Invalid DAB EDI destinations: empty destination"
    )
  end
  list.map(fun (destination) -> "--edi=#{destination}", destinations)
end

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

    let pad_args =
      if
        DAB_METADATA_SOCKET == ""
      then
        []
      else
        let pad_size =
          if DAB_METADATA_SIZE != "" then DAB_METADATA_SIZE else "8" end
        ["--pad=#{pad_size}", "--pad-socket=#{DAB_METADATA_SOCKET}"]
      end
    let edi_args = dab_edi_args(DAB_EDI_DESTINATIONS)
    let odr_command =
      process.quote.command(
        "/bin/odr-audioenc",
        args=
          list.flatten(
            [
              ["-i", "-", "--bitrate=#{DAB_BITRATE}", "--sbr"],
              pad_args,
              edi_args
            ]
          )
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
        reopen_on_error=
          fun (err) ->
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
        odr_command,
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
    description=
      "Show DAB+ TCP acknowledgement health",
    "dab.status",
    fun (_) -> dab_ack_status()
  )
end

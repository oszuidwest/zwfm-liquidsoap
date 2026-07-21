# DAB+ output configuration
# Uses ODR-AudioEnc for DAB+ encoding with EDI output

let DAB_ACK_PID_FILE = "/tmp/dab-ack-monitor/audioenc.pid"
let DAB_ACK_STATE_DIR = "/tmp/dab-ack-monitor/state"

let dab_ack_state = ref("disabled")
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
  let next_state = dab_ack_snapshot_state(snapshot)

  if
    next_state != dab_ack_state()
  then
    let log_level = if next_state == "ok" then 3 else 2 end
    log(
      label="dab",
      "TCP ACK monitor: #{dab_ack_state()} -> #{next_state}",
      level=log_level
    )
    dab_ack_state := next_state
  end

  dab_ack_status := snapshot
end

def dab_ack_monitor_command() =
  "/usr/local/bin/dab-tcp-ack-monitor --pid-file #{
    process.quote(DAB_ACK_PID_FILE)
  } --state-dir #{process.quote(DAB_ACK_STATE_DIR)} --destinations #{
    process.quote(DAB_EDI_DESTINATIONS)
  } --ack-warn-seconds #{DAB_ACK_WARN_SECONDS} --ack-down-seconds #{
    DAB_ACK_DOWN_SECONDS
  } --startup-grace-seconds #{DAB_ACK_STARTUP_GRACE_SECONDS}"
end

def dab_ack_monitor_tick() =
  try
    let snapshot =
      process.read(timeout=5.0, log_errors=false, dab_ack_monitor_command())
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

    # The supervisor only records the child PID and preserves stdin, stderr,
    # signals and the AudioEnc exit status. It does not process the audio.
    let odr_binary =
      if
        DAB_ACK_MONITOR_ENABLED
      then
        "/usr/local/bin/odr-audioenc-supervisor"
      else
        "/bin/odr-audioenc"
      end
    let odr_command =
      ref(
        "#{odr_binary} -i - --bitrate=#{process.quote(DAB_BITRATE)} --sbr"
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
      let poll_seconds =
        if DAB_ACK_POLL_SECONDS < 0.25 then 0.25 else DAB_ACK_POLL_SECONDS end
      thread.run(
        fast=false,
        delay=1.0,
        every=poll_seconds,
        fun () -> dab_ack_monitor_tick()
      )
    else
      dab_set_ack_status(
        "unmonitored\nTCP ACK monitoring is disabled"
      )
    end

    # Feed audio to ODR-AudioEnc. Without reopen_on_error a dead encoder
    # raises a fatal clock error that stops the whole process; returning a
    # delay respawns the encoder instead and leaves other outputs untouched.
    let _ =
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
  else
    dab_set_ack_status(
      "disabled\nDAB+ output is disabled"
    )
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

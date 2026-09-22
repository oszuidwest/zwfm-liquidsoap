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
  or DAB_ACK_DOWN_SECONDS <= DAB_ACK_WARN_SECONDS
  or DAB_ACK_STARTUP_GRACE_SECONDS < 0
then
  failwith(
    "Invalid DAB ACK thresholds: require 0 <= warning < down and startup grace \
     >= 0"
  )
end

# DAB+ health: status is disabled, unmonitored, starting, ok, degraded or down
let dab_ack_status =
  ref(
    {
      status = "disabled",
      detail =
        "DAB+ output is disabled",
      destinations = []
    }
  )

def dab_ack_healthy(status) =
  list.mem(status, ["ok", "starting", "unmonitored", "disabled"])
end

# Stop recurring monitor work before Liquidsoap tears down its internal
# scheduler. Otherwise a tick racing with shutdown cannot enforce the
# process.read timeout and emits a misleading startup warning.
let dab_ack_monitor_running = ref(false)
on_shutdown(fun () -> dab_ack_monitor_running := false)

def dab_set_ack_status(status, detail, ~destinations=[]) =
  let previous = dab_ack_status().status
  if
    status != previous
  then
    log(
      label="dab",
      "TCP ACK monitor: #{previous} -> #{status}",
      level=if dab_ack_healthy(status) then 3 else 2 end
    )
  end
  dab_ack_status :=
    {status = status, detail = detail, destinations = destinations}
end

# The monitor identifies AudioEnc's EDI sockets in ss output by process
# name; a dead encoder is reported by the reopen_on_error handler below.
let dab_ack_monitor_command =
  process.quote.command(
    "/usr/local/bin/dab-tcp-ack-monitor",
    args=[
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

# Parse the monitor's tab-separated destination records. Empty metric fields
# become JSON null values; lines that are not records (monitor errors) are
# kept verbatim in the detail text.
def dab_optional_int(value) =
  if value == "" then null else int_of_string(value) end
end

def dab_parse_ack_destination(line) =
  let fields = string.split(separator="\t", line)
  if
    list.length(fields) != 10
  then
    null
  else
    let [
      destination,
      status,
      tcp_state,
      ack_age,
      bytes_sent,
      bytes_acked,
      send_queue,
      unacked,
      retrans,
      detail
    ] = fields
    {
      destination = destination,
      status = status,
      tcp_state = tcp_state,
      ack_age_seconds = dab_optional_int(ack_age),
      bytes_sent = dab_optional_int(bytes_sent),
      bytes_acked = dab_optional_int(bytes_acked),
      send_queue_bytes = dab_optional_int(send_queue),
      unacked_segments = dab_optional_int(unacked),
      retransmissions = dab_optional_int(retrans),
      detail = detail
    }
  end
end

def dab_parse_ack_monitor(monitor_output) =
  let lines = string.split(separator="\n", string.trim(monitor_output))
  let records = list.tl(lines)
  def describe(line) =
    null.case(
      dab_parse_ack_destination(line),
      {line},
      fun (d) ->
        "#{d.destination} #{d.status} (#{d.detail})"
    )
  end
  {
    status = string.trim(list.hd(default="", lines)),
    detail = string.concat(separator="\n", list.map(describe, records)),
    destinations = list.filter_map(dab_parse_ack_destination, records)
  }
end

# The monitor prints its overall state followed by one record per destination.
def dab_ack_monitor_tick() =
  if
    dab_ack_monitor_running()
  then
    try
      let snapshot =
        dab_parse_ack_monitor(
          process.read(timeout=5.0, log_errors=false, dab_ack_monitor_command)
        )
      if
        snapshot.status == ""
      then
        dab_set_ack_status(
          "down",
          "TCP ACK monitor returned no status"
        )
      else
        dab_set_ack_status(
          snapshot.status,
          snapshot.detail,
          destinations=snapshot.destinations
        )
      end
    catch err do
      dab_set_ack_status(
        "down",
        "TCP ACK monitor error: #{err.kind}: #{err.message}"
      )
    end
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
        "/usr/local/bin/odr-audioenc",
        args=list.flatten(
          [["-i", "-", "--bitrate=#{DAB_BITRATE}", "--sbr"], pad_args, edi_args]
        )
      )

    if
      DAB_ACK_MONITOR_ENABLED
    then
      dab_ack_monitor_running := true
      dab_set_ack_status(
        "starting",
        "Waiting for AudioEnc TCP acknowledgements"
      )
      thread.run(
        fast=false,
        delay=1.0,
        every=max(0.25, DAB_ACK_POLL_SECONDS),
        dab_ack_monitor_tick
      )
    else
      dab_set_ack_status(
        "unmonitored",
        "TCP ACK monitoring is disabled"
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
              "down",
              "DAB+ encoder error: #{err}"
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
    description="Show DAB+ TCP acknowledgement health",
    "dab.status",
    fun (_) ->
      begin
        let s = dab_ack_status()
        "#{s.status}\n#{s.detail}"
      end
  )
end

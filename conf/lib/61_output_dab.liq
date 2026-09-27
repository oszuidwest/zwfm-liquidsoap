# DAB+ EDI output through ODR-AudioEnc.

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

# Public states: disabled, unmonitored, starting, ok, degraded or down.
let dab_ack_status = ref({status = "disabled", destinations = [], error = null})

# Keep encoder failures visible between monitor ticks.
let dab_encoder_error_hold_seconds = 30.0
let dab_encoder_error_at = ref(0.0)

# Avoid monitor timeouts during scheduler shutdown.
let dab_ack_monitor_running = ref(false)
on_shutdown(fun () -> dab_ack_monitor_running := false)

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

def dab_destination_urls(destinations) =
  list.map(
    fun (destination) -> string.trim(destination),
    string.split(separator=",", destinations)
  )
end

def dab_edi_args(destinations) =
  let destinations = dab_destination_urls(destinations)
  if
    list.exists(fun (destination) -> destination == "", destinations)
  then
    failwith(
      "Invalid DAB EDI destinations: empty destination"
    )
  end
  list.map(fun (destination) -> "--edi=#{destination}", destinations)
end

def dab_optional_int(value) =
  if value == "" then null else int_of_string(value) end
end

# Invalid monitor records map to null.
def dab_parse_ack_record(line) =
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
      code
    ] = fields
    {
      destination = destination,
      status = status,
      tcp_state = if tcp_state == "" then null else tcp_state end,
      ack_age_seconds = dab_optional_int(ack_age),
      bytes_sent = dab_optional_int(bytes_sent),
      bytes_acked = dab_optional_int(bytes_acked),
      send_queue_bytes = dab_optional_int(send_queue),
      unacked_segments = dab_optional_int(unacked),
      retransmissions = dab_optional_int(retrans),
      error = if code == "" then null else code end
    }
  end
end

# Keep configured destinations visible when metrics are unavailable.
def dab_configured_destinations(status, failure) =
  list.map(
    fun (destination) ->
      {
        destination = destination,
        status = status,
        tcp_state = null,
        ack_age_seconds = null,
        bytes_sent = null,
        bytes_acked = null,
        send_queue_bytes = null,
        unacked_segments = null,
        retransmissions = null,
        error = failure
      },
    dab_destination_urls(DAB_EDI_DESTINATIONS)
  )
end

# Do not trim: the final tab represents an empty error field.
def dab_parse_ack_monitor(monitor_output) =
  let lines =
    list.filter(
      fun (line) -> line != "",
      string.split(separator="\n", monitor_output)
    )
  let body = list.tl(lines)
  let destinations = list.filter_map(dab_parse_ack_record, body)
  {
    status = string.trim(list.hd(default="", lines)),
    detail =
      if
        list.is_empty(destinations)
      then
        string.concat(
          separator="; ",
          body
        )
      else
        ""
      end,
    destinations = destinations
  }
end

def dab_destination_problems(destinations) =
  string.concat(
    separator="; ",
    list.filter_map(
      fun (d) ->
        null.map(
          fun (error) ->
            "#{d.destination} #{d.status} (#{error})",
          d.error
        ),
      destinations
    )
  )
end

# Aggregate failure details are log-only.
def dab_set_ack_status(status, ~failure=null, ~detail="", ~destinations=null) =
  # Only aggregate failures set the top-level error.
  let failure = if status_healthy(status) then null else failure end
  let destinations =
    destinations ?? dab_configured_destinations(status, failure)

  # Log details only when health changes.
  let previous = dab_ack_status()
  let problems = dab_destination_problems(destinations)
  if
    status != previous.status
    or failure != previous.error
    or problems != dab_destination_problems(previous.destinations)
  then
    let reason =
      if
        null.defined(failure)
      then
        " (#{detail})"
      elsif
        problems != ""
      then
        " (#{problems})"
      else
        ""
      end
    log(
      label="dab",
      "TCP ACK monitor: #{previous.status} -> #{status}#{reason}",
      level=if status_healthy(status) then 3 else 2 end
    )
  end
  dab_ack_status :=
    {status = status, destinations = destinations, error = failure}
end

# Recent encoder failures override ACK health.
def dab_health() =
  let state = dab_ack_status()
  if
    time() - dab_encoder_error_at() < dab_encoder_error_hold_seconds
  then
    {...state, status = "down", error = "encoder_error"}
  else
    state
  end
end

# Include counters only when ACK age is available.
def dab_destination_text(d) =
  let counters =
    null.map(
      fun (ack_age) ->
        "ack_age=#{ack_age}s bytes_sent=#{d.bytes_sent} bytes_acked=#{
          d.bytes_acked
        } send_queue=#{d.send_queue_bytes} unacked=#{d.unacked_segments} \
         retrans=#{d.retransmissions}",
      d.ack_age_seconds
    )
  string.concat(
    separator=" ",
    [
      d.destination,
      d.status,
      ...list.filter_map(fun (part) -> part, [d.error, counters])
    ]
  )
end

def dab_status_text() =
  let health = dab_health()
  let headline =
    null.map(
      fun (code) ->
        "#{health.status}: #{code}",
      health.error
    )
      ?? health.status
  string.concat(
    separator="\n",
    [headline, ...list.map(dab_destination_text, health.destinations)]
  )
end

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
        # Empty records indicate a monitor failure.
        list.is_empty(snapshot.destinations)
      then
        dab_set_ack_status(
          "down",
          failure="monitor_failed",
          detail=if
            snapshot.detail == ""
          then
            "TCP ACK monitor returned no output"
          else
            snapshot.detail
          end
        )
      else
        dab_set_ack_status(snapshot.status, destinations=snapshot.destinations)
      end
    catch err do
      dab_set_ack_status(
        "down",
        failure="monitor_failed",
        detail="TCP ACK monitor error: #{err.kind}: #{err.message}"
      )
    end
  end
end

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

    # Isolate DAB in its own clock domain.
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
      dab_set_ack_status("starting")
      thread.run(
        fast=false,
        delay=1.0,
        every=max(0.25, DAB_ACK_POLL_SECONDS),
        dab_ack_monitor_tick
      )
    else
      dab_set_ack_status("unmonitored")
    end

    # Restart encoder failures without stopping the radio clock.
    ignore(
      output.external(
        %wav(channels = 2, samplerate = 48000),
        reopen_on_error=fun (err) ->
          begin
            dab_encoder_error_at := time()
            log(
              label="dab",
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
    fun (_) -> dab_status_text()
  )
end

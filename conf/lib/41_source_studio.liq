# Studio SRT inputs: silence detection and runtime health.

# GET /status providers, registered once per studio input.
let studio_input_status_providers = ref([])

# Clamp digital silence so status JSON stays finite.
let studio_level_window_seconds = 0.5
let studio_level_floor_dbfs = -120.0

def studio_level_dbfs(connected, amplitude) =
  if
    connected
  then
    float.truncate(
      digits=1,
      max(studio_level_floor_dbfs, min(0.0, dB_of_lin(amplitude)))
    )
  else
    null
  end
end

# Statistics failures preserve the connection and null only its metrics.
def studio_srt_connection(~input_id, peer, read_stats) =
  let unavailable =
    {
      peer = peer,
      latency_ms = null,
      receive_buffer_ms = null,
      rtt_ms = null,
      dropped_packets_total = null,
      statistics_error = null
    }
  try
    let stats = read_stats()
    {
      ...unavailable,
      latency_ms = stats.msRcvTsbPdDelay,
      receive_buffer_ms = stats.msRcvBuf,
      rtt_ms = stats.msRTT,
      dropped_packets_total = stats.pktRcvDropTotal
    }
  catch err do
    log(
      label="status",
      "Unable to read SRT statistics for #{input_id}: #{error.message(err)}",
      level=2
    )
    {
      ...unavailable,
      statistics_error =
        "statistics unavailable"
    }
  end
end

def studio_levels_dbfs(connected, levels) =
  let (left, right) = levels
  {
    left = studio_level_dbfs(connected, left),
    right = studio_level_dbfs(connected, right)
  }
end

# Returns a fallible buffered source; output factories make it safe.
def create_studio_input(~id, ~port) =
  # Require encryption at the SRT listener.
  let studio =
    input.srt(
      id=id,
      port=port,
      mode="listener",
      max=10.0,
      streamid=id,
      enforced_encryption=true,
      passphrase=SRT_PASSPHRASE
    )

  # Log connection transitions.
  studio.on_connect(synchronous=true, fun () -> log_event(id, "connected"))
  studio.on_disconnect(
    synchronous=true,
    fun () -> log_event(id, "disconnected")
  )

  # Pass-through meters preserve the downstream audio.
  let rms_meter =
    rms.stereo(id="rms_#{id}", duration=studio_level_window_seconds, studio)
  let peak_meter =
    peak.stereo(
      id="peak_#{id}",
      duration=studio_level_window_seconds,
      rms_meter
    )

  # Detect and log silence transitions.
  let detected = with_silence_detection(id="detect_#{id}", peak_meter)
  detected.on_blank(
    synchronous=true,
    fun () ->
      log_event(
        id,
        "silence detected"
      )
  )
  detected.on_noise(
    synchronous=true,
    fun () ->
      log_event(
        id,
        "audio resumed"
      )
  )

  # Strip silence so the fallback chain can advance.
  let stripped = with_silence_strip(id="strip_#{id}", detected)

  # Disabling silence detection leaves only disconnection-triggered fallback.
  let switched =
    switch(
      id="#{id}_output",
      track_sensitive=false,
      [
        ({is_silence_detection_enabled()}, stripped),
        ({not is_silence_detection_enabled()}, peak_meter)
      ]
    )

  # Drain into the shared clock so a disconnected standby input's buffer expires
  # and fallback stops treating it as ready.
  let buffered =
    buffer(
      id="buffered_#{id}",
      buffer=1.0,
      max=1.25,
      fallible=true,
      replay_metadata=false,
      add_track_mark=false,
      switched
    )
  output.dummy(id="drain_#{id}", fallible=true, register_telnet=false, buffered)

  # Public HTTP snapshots redact peers; local server commands include them.
  def status(~include_peer) =
    let sockets = studio.sockets()
    let connections =
      list.map(
        fun (connection) ->
          begin
            let (peer, raw_socket) = connection
            studio_srt_connection(
              input_id=id,
              if include_peer then peer else null end,
              fun () -> srt.socket(raw_socket).bistats()
            )
          end,
        sockets
      )
    let connected = not list.is_empty(sockets)

    {
      name = id,
      buffer_seconds = seconds_of_main(buffered.buffer_length()),
      audio =
        {
          window_seconds = studio_level_window_seconds,
          rms_dbfs = studio_levels_dbfs(connected, rms_meter.rms()),
          peak_dbfs = studio_levels_dbfs(connected, peak_meter.peak())
        },
      srt = {connected = connected, connections = connections}
    }
  end
  studio_input_status_providers :=
    list.append(studio_input_status_providers(), [status])

  # Surface buffer readiness for clock-drift diagnostics.
  server.register(
    description="Show readiness and buffered seconds for #{id}",
    "#{id}.buffer",
    fun (_) ->
      "ready=#{source.is_ready(buffered)}, buffer=#{
        seconds_of_main(buffered.buffer_length())
      }s"
  )

  server.register(
    description="Show SRT latency and receive health for #{id}",
    "#{id}.srt",
    fun (_) ->
      begin
        let snapshot = status(include_peer=true)
        let details =
          string.concat(
            separator="; ",
            list.map(
              fun (connection) ->
                if
                  null.defined(connection.statistics_error)
                then
                  "peer=#{connection.peer}, statistics unavailable"
                else
                  "peer=#{connection.peer}, latency=#{
                    connection.latency_ms
                  }ms, buffer=#{connection.receive_buffer_ms}ms, rtt=#{
                    connection.rtt_ms
                  }ms, dropped_total=#{connection.dropped_packets_total}"
                end,
              snapshot.srt.connections
            )
          )

        if
          snapshot.srt.connected
        then
          "connected=true, #{details}"
        else
          "connected=false"
        end
      end
  )
  buffered
end

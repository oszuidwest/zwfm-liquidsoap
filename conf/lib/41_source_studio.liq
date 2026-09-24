# Studio SRT input factory
# Creates SRT inputs with silence detection and connection handling

# Runtime health providers registered by each studio input, read by GET /status.
let studio_input_status_providers = ref([])

# Stereo RMS and peak meters use the same short window. Digital silence is
# clamped to a practical floor so the JSON never contains negative infinity.
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

# Factory function to create a studio SRT input
# Returns a fallible, buffered source; output factories add their own mksafe()
def create_studio_input(~id, ~port) =
  # Create SRT input with encryption
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

  # Attach connection logging callbacks
  studio.on_connect(synchronous=true, fun () -> log_event(id, "connected"))
  studio.on_disconnect(
    synchronous=true,
    fun () -> log_event(id, "disconnected")
  )

  # Pass-through analyzers expose independent left/right levels without
  # altering the audio sent to silence detection and the radio chain.
  let rms_meter =
    rms.stereo(id="rms_#{id}", duration=studio_level_window_seconds, studio)
  let peak_meter =
    peak.stereo(
      id="peak_#{id}",
      duration=studio_level_window_seconds,
      rms_meter
    )

  # Add silence detection with logging
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

  # Strip silence to trigger fallback
  let stripped = with_silence_strip(id="strip_#{id}", detected)

  # Return source based on silence detection state
  # When enabled: use stripped version (triggers fallback on silence)
  # When disabled: use raw studio (only disconnection triggers fallback)
  let switched =
    switch(
      id="#{id}_output",
      track_sensitive=false,
      [
        ({is_silence_detection_enabled()}, stripped),
        ({not is_silence_detection_enabled()}, peak_meter)
      ]
    )

  # Bridge the SRT input to the shared radio clock. Continuously consume the
  # producer side so buffered audio from a disconnected standby input expires
  # and fallback no longer considers that input ready.
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

  # One structured snapshot feeds the server command and GET /status. Peer
  # addresses are only included for callers allowed to see them.
  def status(~include_peer) =
    let connections =
      list.filter_map(
        fun (connection) ->
          try
            let (peer, raw_socket) = connection
            let stats = srt.socket(raw_socket).bistats()
            {
              peer = if include_peer then peer else null end,
              latency_ms = stats.msRcvTsbPdDelay,
              receive_buffer_ms = stats.msRcvBuf,
              rtt_ms = stats.msRTT,
              dropped_packets_total = stats.pktRcvDropTotal
            }
          catch err do
            log(
              label="status",
              "Unable to read SRT statistics for #{id}: #{error.message(err)}",
              level=2
            )
            null
          end,
        studio.sockets()
      )
    let connected = not list.is_empty(connections)
    let (rms_left, rms_right) = rms_meter.rms()
    let (peak_left, peak_right) = peak_meter.peak()

    {
      name = id,
      ready = source.is_ready(buffered),
      buffer_seconds = seconds_of_main(buffered.buffer_length()),
      audio =
        {
          window_seconds = studio_level_window_seconds,
          rms_dbfs =
            {
              left = studio_level_dbfs(connected, rms_left),
              right = studio_level_dbfs(connected, rms_right)
            },
          peak_dbfs =
            {
              left = studio_level_dbfs(connected, peak_left),
              right = studio_level_dbfs(connected, peak_right)
            }
        },
      srt = {connected = connected, connections = connections}
    }
  end
  studio_input_status_providers :=
    list.append(studio_input_status_providers(), [status])

  # Expose buffer health for diagnosing clock drift.
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
                "peer=#{connection.peer}, latency=#{connection.latency_ms}ms, \
                 buffer=#{connection.receive_buffer_ms}ms, rtt=#{
                  connection.rtt_ms
                }ms, dropped_total=#{connection.dropped_packets_total}",
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

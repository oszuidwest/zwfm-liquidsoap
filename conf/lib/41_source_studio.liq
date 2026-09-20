# Studio SRT input factory
# Creates SRT inputs with silence detection and connection handling

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

  # Add silence detection with logging
  let detected = with_silence_detection(id="detect_#{id}", studio)
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
        ({not is_silence_detection_enabled()}, studio)
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
        let connections =
          list.map(
            fun (connection) ->
              begin
                let (peer, raw_socket) = connection
                let srt_connection = srt.socket(raw_socket)
                let stats = srt_connection.bistats()
                "peer=#{peer}, latency=#{stats.msRcvTsbPdDelay}ms, buffer=#{
                  stats.msRcvBuf
                }ms, rtt=#{stats.msRTT}ms"
              end,
            studio.sockets()
          )
        let details =
          string.concat(
            separator="; ",
            connections
          )

        if
          details == ""
        then
          "connected=false"
        else
          "connected=true, #{details}"
        end
      end
  )
  buffered
end

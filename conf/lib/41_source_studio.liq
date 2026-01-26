# Studio SRT input factory
# Creates SRT inputs with silence detection and connection handling

# Factory function to create a studio SRT input
# Returns a fallible source - output factories handle buffering and mksafe()
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
  switch(
    id="#{id}_output",
    track_sensitive=false,
    [
      ({is_silence_detection_enabled()}, stripped),
      ({not is_silence_detection_enabled()}, studio)
    ]
  )
end

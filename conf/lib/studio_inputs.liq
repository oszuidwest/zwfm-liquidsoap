# Studio inputs configuration - common for all stations

# Get SRT passphrase for encryption
SRT_PASSPHRASE = environment.get("SRT_PASSPHRASE")

# Note: SILENCE_CONTROL_PATH and is_silence_detection_enabled() are defined in defaults.liq

# Function to create a studio SRT input with silence detection and buffering
def create_studio_input(~input_id, ~port) =
  # Create SRT input
  studio =
    input.srt(
      id=input_id,
      port=port,
      mode="listener",
      max=10.0,
      streamid=input_id,
      enforced_encryption=true,
      passphrase=SRT_PASSPHRASE,
      on_connect=fun () -> log_event(input_id, "connected"),
      on_disconnect=fun () -> log_event(input_id, "disconnected")
    )

  # Create version with silence detection
  # In Liquidsoap 2.4+, callbacks are attached via source methods
  studio_with_detect =
    blank.detect(
      id="detect_#{input_id}",
      max_blank=SILENCE_SWITCH_SECONDS,
      min_noise=AUDIO_VALID_SECONDS,
      threshold=SILENCE_THRESHOLD,
      studio
    )

  # Attach silence detection callbacks using source methods (2.4+ API)
  studio_with_detect.on_blank(
    synchronous=true,
    fun () -> log_event(input_id, "silence detected")
  )

  studio_with_detect.on_noise(
    synchronous=true,
    fun () -> log_event(input_id, "audio resumed")
  )

  studio_stripped =
    blank.strip(
      id="stripped_#{input_id}",
      max_blank=SILENCE_SWITCH_SECONDS,
      min_noise=AUDIO_VALID_SECONDS,
      threshold=SILENCE_THRESHOLD,
      studio_with_detect
    )

  # Use switch to select between stripped version and original
  studio_switchable =
    switch(
      id="switch_silence_#{input_id}",
      track_sensitive=false,
      [
        ({is_silence_detection_enabled()}, studio_stripped),
        # When silence detection is disabled, use raw studio source
        ({not (is_silence_detection_enabled())}, studio)
      ]
    )

  # Buffer to prevent connection/disconnection latency impact
  buffer(id="buffered_#{input_id}", fallible=true, studio_switchable)
end

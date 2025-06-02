# Studio inputs configuration - common for all stations

# Get upstream password for SRT encryption
UPSTREAM_PASSWORD = environment.get("UPSTREAM_PASSWORD")

# Note: SILENCE_DETECTION_FILE and is_silence_detection_enabled() are defined in defaults.liq

# Function to create a studio SRT input with silence detection and buffering
def create_studio_input(~id, ~port) =
  # Create SRT input
  studio =
    input.srt(
      id=id,
      port=port,
      mode="listener",
      max=10.0,
      streamid=id,
      enforced_encryption=true,
      passphrase=UPSTREAM_PASSWORD,
      on_connect=fun () -> log_event(id, "connected"),
      on_disconnect=fun () -> log_event(id, "disconnected")
    )

  # Create version with silence detection and stripping
  studio_with_detect =
    blank.detect(
      id="detect_#{id}",
      max_blank=MAX_BLANK,
      min_noise=MIN_NOISE,
      fun () ->
        log_event(
          id,
          "silence detected"
        ),
      on_noise=
        fun () ->
          log_event(
            id,
            "audio resumed"
          ),
      studio
    )

  studio_stripped =
    blank.strip(
      id="stripped_#{id}",
      max_blank=MAX_BLANK,
      min_noise=MIN_NOISE,
      studio_with_detect
    )

  # Use switch to select between stripped version and original
  studio_switchable =
    switch(
      id="switch_silence_#{id}",
      track_sensitive=false,
      [
        ({is_silence_detection_enabled()}, studio_stripped),
        # When silence detection is disabled, use raw studio source
        ({true}, studio)
      ]
    )

  # Buffer to prevent connection/disconnection latency impact
  buffer(id="buffered_#{id}", fallible=true, studio_switchable)
end

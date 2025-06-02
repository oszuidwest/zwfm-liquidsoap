# Studio inputs configuration - common for all stations

# Get upstream password for SRT encryption
UPSTREAM_PASSWORD = environment.get("UPSTREAM_PASSWORD")

# Note: SILENCE_DETECTION_FILE must be defined before including this file (it's in defaults.liq)

# Track the last known silence detection state
silence_detection_state = ref(true)

# Function to check if silence detection is enabled
def is_silence_detection_enabled() =
  current_state =
    if
      file.exists(SILENCE_DETECTION_FILE)
    then
      file_content = file.contents(SILENCE_DETECTION_FILE)
      first_char = list.hd(string.chars(file_content))
      first_char == "1"
    else
      # Default to enabled if file doesn't exist
      true
    end

  # Log if state has changed
  if
    current_state != !silence_detection_state
  then
    silence_detection_state := current_state
    if
      current_state
    then
      log(
        "Silence detection ENABLED",
        level=3
      )
    else
      log(
        "Silence detection DISABLED",
        level=3
      )
    end
  end

  current_state
end

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

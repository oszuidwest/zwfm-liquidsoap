# Studio inputs configuration - common for all stations

# Get SRT passphrase for encryption
SRT_PASSPHRASE = environment.get("SRT_PASSPHRASE")

# Note: is_silence_detection_enabled() is defined in defaults.liq

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
      passphrase=SRT_PASSPHRASE
    )

  # Attach connection callbacks using source methods (2.4+ API)
  studio.on_connect(synchronous=true, fun () -> log_event(input_id, "connected"))
  studio.on_disconnect(synchronous=true, fun () -> log_event(input_id, "disconnected"))

  # Create version with silence detection (uses centralized params from defaults.liq)
  studio_with_detect = add_silence_detection(id="detect_#{input_id}", studio)

  # Attach silence detection callbacks
  studio_with_detect.on_blank(
    synchronous=true,
    fun () ->
      log_event(
        input_id,
        "silence detected"
      )
  )

  studio_with_detect.on_noise(
    synchronous=true,
    fun () ->
      log_event(
        input_id,
        "audio resumed"
      )
  )

  # Strip silence to trigger fallback (uses centralized params from defaults.liq)
  studio_stripped = add_silence_strip(id="stripped_#{input_id}", studio_with_detect)

  # Use switch to select between stripped version and original
  # Returns fallible source - output factories handle buffering and mksafe()
  switch(
    id="switch_silence_#{input_id}",
    track_sensitive=false,
    [
      ({is_silence_detection_enabled()}, studio_stripped),
      # When silence detection is disabled, use raw studio source
      ({not (is_silence_detection_enabled())}, studio)
    ]
  )
end

# Studio inputs configuration - common for all stations

# Function to create a studio SRT input with silence detection and buffering
def create_studio_input(~id, ~port) =
  # Create SRT input
  s =
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

  # Add silence detection with logging
  s =
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
      s
    )

  # Strip blanks to make source unavailable when silent
  s = blank.strip(id="stripped_#{id}", max_blank=MAX_BLANK, min_noise=MIN_NOISE, s)

  # Buffer to prevent connection/disconnection latency impact
  buffer(id="buffered_#{id}", fallible=true, s)
end

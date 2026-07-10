# Emergency fallback source
# Provides audio when all studio inputs fail
#
# The emergency audio file is a required production dependency. Startup
# fails when the file is missing or cannot be decoded, so a broken
# deployment surfaces immediately instead of as dead air later. Setting
# EMERGENCY_ALLOW_BLANK=true explicitly opts in to a silent fallback
# for development and testing.

# Inspect the configured emergency audio file
# Returns ("", duration in seconds) when the file is usable, or
# (problem description, 0.) when not
def emergency_audio_status() =
  if
    not file.exists(EMERGENCY_AUDIO_PATH)
  then
    (
      "file does not exist",
      0.
    )
  else
    let audio_duration = request.duration(EMERGENCY_AUDIO_PATH) ?? 0.
    if
      audio_duration <= 0.
    then
      (
        "file cannot be decoded as audio",
        0.
      )
    else
      ("", audio_duration)
    end
  end
end

# Build the emergency fallback audio source
# Fails fast (exit 1) when the configured file is unusable, unless a
# silent fallback was explicitly allowed via EMERGENCY_ALLOW_BLANK=true
def create_fallback_audio() =
  let (problem, audio_duration) = emergency_audio_status()
  if
    problem == ""
  then
    log(
      level=3,
      label="fallback",
      "Emergency fallback audio OK: #{EMERGENCY_AUDIO_PATH} (duration: #{
        audio_duration
      }s)"
    )
    source.drop.metadata(id="fallback_file", single(EMERGENCY_AUDIO_PATH))
  elsif
    EMERGENCY_ALLOW_BLANK
  then
    let warning =
      "Emergency fallback audio #{problem}: #{EMERGENCY_AUDIO_PATH}. \
       EMERGENCY_ALLOW_BLANK=true, so a SILENT fallback is used. Dead air will \
       be broadcast when all studio inputs fail."
    log(level=2, label="fallback", warning)
    print(
      "WARNING: #{warning}"
    )
    blank(id="fallback_blank")
  else
    let message =
      "Emergency fallback audio #{problem}: #{EMERGENCY_AUDIO_PATH}"
    log(level=1, label="fallback", message)
    print(
      "FATAL: #{message}"
    )
    print(
      "Fix: provide a decodable audio file at this path (configured via \
       EMERGENCY_AUDIO_PATH), or set EMERGENCY_ALLOW_BLANK=true to explicitly \
       accept a silent fallback for development/testing."
    )
    exit(1)

    # Unreachable - exit(1) terminates, but the branch must yield a source
    blank(id="fallback_blank")
  end
end

# Create fallback audio source - validated file, or blank when explicitly
# allowed
let fallback_audio = create_fallback_audio()

# Blank source for when silence detection is disabled
let fallback_disabled = blank(id="fallback_disabled")

# Emergency fallback with silence detection awareness
# When silence detection is enabled: plays fallback audio
# When silence detection is disabled: outputs silence (blank)
let emergency_fallback =
  switch(
    id="emergency_fallback",
    track_sensitive=false,
    [
      ({is_silence_detection_enabled()}, fallback_audio),
      ({true}, fallback_disabled)
    ]
  )

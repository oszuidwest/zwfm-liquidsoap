# Emergency fallback source
# Provides audio when all studio inputs fail
#
# The emergency audio file is validated at startup: a missing or
# undecodable file aborts startup instead of surfacing as dead air later,
# unless EMERGENCY_ALLOW_BLANK=true opts in to a silent fallback.

# Probe the configured emergency audio file; empty string when usable
let fallback_problem =
  if
    not file.exists(EMERGENCY_AUDIO_PATH)
  then
    "file does not exist"
  elsif
    (request.duration(EMERGENCY_AUDIO_PATH) ?? 0.) <= 0.
  then
    "file cannot be decoded as audio"
  else
    ""
  end

# Create fallback audio source - validated file, or blank when explicitly
# allowed
let fallback_audio =
  if
    fallback_problem == ""
  then
    log.important(
      label="fallback",
      "Emergency fallback audio OK: #{EMERGENCY_AUDIO_PATH}"
    )
    source.drop.metadata(id="fallback_file", single(EMERGENCY_AUDIO_PATH))
  elsif
    EMERGENCY_ALLOW_BLANK
  then
    log.severe(
      label="fallback",
      "Emergency fallback audio #{fallback_problem}: #{EMERGENCY_AUDIO_PATH}. \
       EMERGENCY_ALLOW_BLANK=true, so a SILENT fallback is used. Dead air will \
       be broadcast when all studio inputs fail."
    )
    blank(id="fallback_blank")
  else
    error.raise(
      error.invalid,
      "Emergency fallback audio #{fallback_problem}: #{EMERGENCY_AUDIO_PATH}. \
       Provide a decodable audio file at this path, or set \
       EMERGENCY_ALLOW_BLANK=true to explicitly accept a silent fallback for \
       development/testing."
    )
  end

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

# Emergency fallback source
# Provides audio when all studio inputs fail

# Create fallback audio source - either from file or blank
let fallback_audio =
  if
    file.exists(EMERGENCY_AUDIO_PATH)
  then
    source.drop.metadata(id="fallback_file", single(EMERGENCY_AUDIO_PATH))
  else
    blank(id="fallback_blank")
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

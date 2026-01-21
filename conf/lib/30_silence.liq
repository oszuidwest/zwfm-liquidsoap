# Silence detection helpers
# Wrappers for blank.detect and blank.strip with centralized parameters

# Wrap source with silence detection (for logging)
# Uses centralized threshold parameters from 00_settings.liq
def with_silence_detection(~id, s) =
  blank.detect(
    id=id,
    max_blank=SILENCE_SWITCH_SECONDS,
    min_noise=AUDIO_VALID_SECONDS,
    threshold=SILENCE_THRESHOLD,
    s
  )
end

# Wrap source with silence stripping (triggers fallback on silence)
# Uses centralized threshold parameters from 00_settings.liq
def with_silence_strip(~id, s) =
  blank.strip(
    id=id,
    max_blank=SILENCE_SWITCH_SECONDS,
    min_noise=AUDIO_VALID_SECONDS,
    threshold=SILENCE_THRESHOLD,
    s
  )
end

# Include default configuration values
%include "lib/defaults.liq"

# Include library configurations
%include "lib/studio_inputs.liq"
%include "lib/stereotool.liq"

# Create the two studio inputs
studio_a = create_studio_input(id="studio_a", port=8888)
studio_b = create_studio_input(id="studio_b", port=9999)

# Combine live inputs and fallback
radio =
  fallback(
    id="radio_prod",
    track_sensitive=false,
    [studio_a, studio_b, emergency_fallback]
  )

# Create processed/unprocessed audio sources
# When StereoTool is enabled (STEREOTOOL_LICENSE_KEY is set), it provides:
# - Audio processing (AGC, compression, limiting, etc.)
# - MicroMPX encoding for FM transmitters (available on separate StereoTool output)
# Two audio sources are available:
# - 'radio': Unprocessed audio (direct from studio/fallback)
# - 'radio_processed': Either StereoTool-processed audio (if enabled) or unprocessed audio (if disabled)
radio_processed = create_processed_audio(radio)

# Create a clock for DAB+ output
audio_to_dab = mksafe(buffer(radio_processed))
clock.assign_new(id="dab_clock", [audio_to_dab])

# Include Icecast outputs configuration
%include "lib/icecast_outputs.liq"

# Output a high bitrate mp3 stream
output_icecast_stream(
  format=%mp3(bitrate = 192, samplerate = 48000, internal_quality = 0),
  description=
    "Hoge Kwaliteit Stream (192kbit MP3)",
  mount=HIGH_QUALITY_MOUNT,
  source=radio_processed
)

# Output a low bitrate AAC stream
output_icecast_stream(
  format=
    %fdkaac(
      channels = 2,
      samplerate = 48000,
      bitrate = 96,
      afterburner = true,
      aot = 'mpeg4_aac_lc',
      transmux = 'adts',
      sbr_mode = true
    ),
  description=
    "Mobile Stream (96kbit AAC)",
  mount=MOBILE_MOUNT,
  source=radio_processed
)

# Output a high bitrate AAC STL stream
output_icecast_stream(
  format=
    %fdkaac(
      channels = 2,
      samplerate = 48000,
      bitrate = 576,
      afterburner = true,
      aot = 'mpeg4_aac_lc',
      transmux = 'adts',
      sbr_mode = true
    ),
  description=
    "Transport Stream (576kbit AAC)",
  mount=TRANSPORT_MOUNT,
  source=radio_processed
)

# Feed the audio to ODR-AudioEnc
output.external(
  %wav(channels = 2, samplerate = 48000),
  "/bin/odr-audioenc -i - --bitrate=#{ODR_AUDIOENC_BITRATE} \
   --stats=/tmp/dab_stats.sock --edi='#{ODR_AUDIOENC_EDI_URL}'",
  audio_to_dab
)

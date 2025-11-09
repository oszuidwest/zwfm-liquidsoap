# Include default configuration values
%include "lib/defaults.liq"

# Include library configurations
%include "lib/studio_inputs.liq"
%include "lib/stereotool.liq"

# Create the two studio inputs
studio_a = create_studio_input(id="studio_a", port=SRT_PORT_PRIMARY)
studio_b = create_studio_input(id="studio_b", port=SRT_PORT_SECONDARY)

# Combine live inputs and fallback
radio =
  fallback(
    id="radio_prod",
    track_sensitive=false,
    [studio_a, studio_b, emergency_fallback]
  )

# Create processed/unprocessed audio sources
# When StereoTool is enabled (STEREOTOOL_LICENSE is set), it provides:
# - Audio processing (AGC, compression, limiting, etc.)
# - MicroMPX encoding for FM transmitters (available in StereoTool itself)
# Two audio sources are available:
# - 'radio': Unprocessed audio (direct from studio/fallback)
# - 'radio_processed': Either StereoTool-processed audio (if enabled) or unprocessed audio (if disabled)
radio_processed = create_processed_audio(radio)

# Include output configurations
%include "lib/icecast_outputs.liq"
%include "lib/dab_output.liq"

# Output a high bitrate mp3 stream using ffmpeg encoder
output_icecast_stream(
  format=%ffmpeg(
    format = "mp3",
    %audio(
      codec = "libmp3lame",
      b = "#{ICECAST_BITRATE_MP3}k",
      ar = 48000,
      ac = 2
    )
  ),
  description="Hoge Kwaliteit Stream (192kbit MP3)",
  mount=ICECAST_MOUNT_MP3,
  source=radio
)

# Output a low bitrate AAC stream
output_icecast_stream(
  format=%fdkaac(
    channels = 2,
    samplerate = 48000,
    bitrate = ICECAST_BITRATE_AAC_LOW,
    afterburner = true,
    aot = 'mpeg4_aac_lc',
    transmux = 'adts',
    sbr_mode = true
  ),
  description="Mobile Stream (96kbit AAC)",
  mount=ICECAST_MOUNT_AAC_LOW,
  source=radio
)

# Output a high bitrate AAC STL stream
output_icecast_stream(
  format=%fdkaac(
    channels = 2,
    samplerate = 48000,
    bitrate = ICECAST_BITRATE_AAC_HIGH,
    afterburner = true,
    aot = 'mpeg4_aac_lc',
    transmux = 'adts',
    sbr_mode = true
  ),
  description="Transport Stream (576kbit AAC)",
  mount=ICECAST_MOUNT_AAC_HIGH,
  source=radio
)

# Output to DAB+
output_dab_stream(radio)

# ZuidWest FM - Station configuration
# Uses unprocessed audio for all outputs

# Load libraries in order
%include "lib/00_settings.liq"
%include "lib/10_logging.liq"
%include "lib/20_state.liq"
%include "lib/30_silence.liq"
%include "lib/40_source_fallback.liq"
%include "lib/41_source_studio.liq"
%include "lib/50_processing.liq"
%include "lib/60_output_icecast.liq"
%include "lib/61_output_dab.liq"
%include "lib/80_server.liq"
%include "lib/90_radio.liq"

# Create the two studio inputs
let studio_a = create_studio_input(id="studio_a", port=SRT_PORT_PRIMARY)
let studio_b = create_studio_input(id="studio_b", port=SRT_PORT_SECONDARY)

# Build radio source with fallback chain, force support, and server commands
let radio =
  create_radio(
    sources=[
      ("studio_a", studio_a),
      ("studio_b", studio_b),
      ("fallback", emergency_fallback)
    ]
  )

# Activate StereoTool for MicroMPX transport (not used in Liquidsoap audio chain)
# output.dummy() is required to pull the stereotool source and keep processing active
let processed = create_processed_audio(radio)
output.dummy(processed)

# Output streams - ZuidWest uses unprocessed audio
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
  audio_source=radio
)

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
  audio_source=radio
)

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
  audio_source=radio
)

# DAB+ output
output_dab_stream(radio)

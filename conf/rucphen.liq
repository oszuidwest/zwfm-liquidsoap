# Include default configuration values
%include "lib/defaults.liq"

# Configuration variables
ICECAST_NAME = environment.get("ICECAST_NAME")
ICECAST_SERVER = environment.get("ICECAST_SERVER")
ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT", default="80"))
ICECAST_PASSWORD = environment.get("ICECAST_PASSWORD")

# Note: FALLBACK_FILE and USE_NOODBAND_FILE are defined in defaults.liq
UPSTREAM_PASSWORD = environment.get("UPSTREAM_PASSWORD")

# StereoTool configuration
STEREOTOOL_LICENSE_KEY = environment.get("STEREOTOOL_LICENSE_KEY")

# Dutch Media Exchange (DME) configuration
DME_INGEST_A_HOST = environment.get("DME_INGEST_A_HOST", default="in1.media-exchange.nl")
DME_INGEST_A_PORT = int_of_string(environment.get("DME_INGEST_A_PORT", default="8005"))
DME_INGEST_A_USER = environment.get("DME_INGEST_A_USER")
DME_INGEST_A_PASSWORD = environment.get("DME_INGEST_A_PASSWORD")

DME_INGEST_B_HOST = environment.get("DME_INGEST_B_HOST", default="in2.media-exchange.nl")
DME_INGEST_B_PORT = int_of_string(environment.get("DME_INGEST_B_PORT", default="8210"))
DME_INGEST_B_USER = environment.get("DME_INGEST_B_USER")
DME_INGEST_B_PASSWORD = environment.get("DME_INGEST_B_PASSWORD")

DME_MOUNT = environment.get("DME_MOUNT")
DME_NAME = environment.get("DME_NAME")
DME_DESCRIPTION = environment.get("DME_DESCRIPTION")

# ODR-AudioEnc configuration
ODR_AUDIOENC_BITRATE = int_of_string(environment.get("ODR_AUDIOENC_BITRATE"))
ODR_AUDIOENC_EDI_URL = environment.get("ODR_AUDIOENC_EDI_URL")

# Icecast stream descriptions and mounts
ICECAST_MOUNTPOINT = environment.get("ICECAST_MOUNTPOINT")
HIGH_QUALITY_MOUNT = environment.get("HIGH_QUALITY_MOUNT", default="/#{ICECAST_MOUNTPOINT}.mp3")
MOBILE_MOUNT = environment.get("MOBILE_MOUNT", default="/#{ICECAST_MOUNTPOINT}.aac")
TRANSPORT_MOUNT = environment.get("TRANSPORT_MOUNT", default="/#{ICECAST_MOUNTPOINT}.stl")

# Note: MAX_BLANK, MIN_NOISE, audio settings, and log_event are defined in defaults.liq

# The noodband source file
noodband_file = source.drop.metadata(id="noodband_file", single(FALLBACK_FILE))
silence = blank()

# Get the current noodband source
def get_noodband_source() =
  use_noodband = ref(true)

  if
    file.exists(USE_NOODBAND_FILE)
  then
    x = file.contents(USE_NOODBAND_FILE)
    check = list.hd(string.chars(x))
    use_noodband := check == "1"
  end

  if use_noodband() then noodband_file else silence end
end

# Backup file to be played when no audio is coming from the studio, or silence when noodband is disabled.
noodband =
  source.dynamic(id="Noodband", infallible=true, init=blank(), fun () -> get_noodband_source())

# Track the current noodband source to detect changes
current_noodband_source = ref("")

# Check for noodband source changes and log only when changed
def check_noodband_source() =
  new_source = noodband.current_source()
  new_source_id = if null.defined(new_source) then source.id(null.get(new_source)) else "none" end
  if
    new_source_id != current_noodband_source()
  then
    current_noodband_source := new_source_id
    log(
      "Noodband source changed to: #{new_source_id}"
    )
  end
end

# Check periodically but only log on changes
thread.run(every=1., check_noodband_source)

# Include studio inputs configuration
%include "lib/studio_inputs.liq"

# Create the two studio inputs
studio_a = create_studio_input(id="studio_a", port=8888)
studio_b = create_studio_input(id="studio_b", port=9999)

# Combine live inputs and fallback
radio = fallback(id="radio_prod", track_sensitive=false, [studio_a, studio_b, noodband])

# StereoTool implementation
radioproc =
  stereotool(
    library_file="/var/cache/liquidsoap/st_plugin.so",
    license_key=STEREOTOOL_LICENSE_KEY,
    preset="/var/cache/liquidsoap/.st_plugin.so.rc",
    radio
  )

# Send unprocessed audio to a dummy output since we only use it as StereoTool input
output.dummy(radio)

# Create a clock for output to Radio Netwerk Nederland
audio_to_rnn = mksafe(buffer(radioproc))
clock.assign_new(id="rnn_clock", [audio_to_rnn])

# Include Icecast outputs configuration
%include "lib/icecast_outputs.liq"

# Note: Each Icecast output automatically creates its own clock for stability

# Output a high bitrate mp3 stream
output_icecast_stream(
  format=%mp3(bitrate = 192, samplerate = 48000, internal_quality = 0),
  description=
    "Hoge Kwaliteit Stream (192kbit MP3)",
  mount=HIGH_QUALITY_MOUNT,
  source=radioproc
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
  source=radioproc
)

# Output a high bitrate AAC stream (STL - Studio to Transmitter Link)
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
  source=radioproc
)

# Output high bitrate AAC streams to Dutch Media Exchange (A and B)
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
  description=DME_DESCRIPTION,
  mount=DME_MOUNT,
  source=radioproc,
  host=DME_INGEST_A_HOST,
  port=DME_INGEST_A_PORT,
  password=DME_INGEST_A_PASSWORD,
  name=DME_NAME,
  user=DME_INGEST_A_USER
)

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
  description=DME_DESCRIPTION,
  mount=DME_MOUNT,
  source=radioproc,
  host=DME_INGEST_B_HOST,
  port=DME_INGEST_B_PORT,
  password=DME_INGEST_B_PASSWORD,
  name=DME_NAME,
  user=DME_INGEST_B_USER
)

# Feed the audio to ODR-AudioEnc
output.external(
  %wav(channels = 2, samplerate = 48000),
  "/bin/odr-audioenc -i - --bitrate=#{ODR_AUDIOENC_BITRATE} --stats=/dabplus/sockets/dab_stats \
   --edi='#{ODR_AUDIOENC_EDI_URL}'",
  audio_to_rnn
)

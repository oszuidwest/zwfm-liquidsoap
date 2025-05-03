# Configuration variables
ICECAST_NAME = environment.get("ICECAST_NAME")
ICECAST_SERVER = environment.get("ICECAST_SERVER")
ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT", default="80"))
ICECAST_PASSWORD = environment.get("ICECAST_PASSWORD")
FALLBACK_FILE = environment.get("FALLBACK_FILE", default="/audio/fallback.mp3")
USE_NOODBAND_FILE =
  environment.get("USE_NOODBAND_FILE", default="/use_noodband.txt")
UPSTREAM_PASSWORD = environment.get("UPSTREAM_PASSWORD")

# StereoTool configuration
STEREOTOOL_LICENSE_KEY = environment.get("STEREOTOOL_LICENSE_KEY")

# Dutch Media Exchange (DME) configuration
DME_INGEST_A_HOST =
  environment.get("DME_INGEST_A_HOST", default="in1.media-exchange.nl")
DME_INGEST_A_PORT =
  int_of_string(environment.get("DME_INGEST_A_PORT", default="8005"))
DME_INGEST_A_USER = environment.get("DME_INGEST_A_USER")
DME_INGEST_A_PASSWORD = environment.get("DME_INGEST_A_PASSWORD")

DME_INGEST_B_HOST =
  environment.get("DME_INGEST_B_HOST", default="in2.media-exchange.nl")
DME_INGEST_B_PORT =
  int_of_string(environment.get("DME_INGEST_B_PORT", default="8210"))
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
HIGH_QUALITY_MOUNT =
  environment.get("HIGH_QUALITY_MOUNT", default="/#{ICECAST_MOUNTPOINT}.mp3")
MOBILE_MOUNT =
  environment.get("MOBILE_MOUNT", default="/#{ICECAST_MOUNTPOINT}.aac")
TRANSPORT_MOUNT =
  environment.get("TRANSPORT_MOUNT", default="/#{ICECAST_MOUNTPOINT}.stl")

# Silence detection configuration
MAX_BLANK = float_of_string(environment.get("MAX_BLANK", default="15.0"))
MIN_NOISE = float_of_string(environment.get("MIN_NOISE", default="15.0"))

# Audio defaults
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Logging function for various events
def log_event(input_name, event) =
  log(
    "#{input_name} #{event}",
    level=3
  )
end

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
  source.dynamic(
    id="Noodband",
    infallible=true,
    init=blank(),
    fun () -> get_noodband_source()
  )

# TODO: Log when the source changes, instead of logging every x seconds
# Log the current noodband source every 5 seconds
thread.run(
  every=5.,
  {
    log(
      "Noodband is using #{noodband.current_source()}"
    )
  }
)

# Input for primary studio stream
studio_a =
  input.srt(
    id="studio_a",
    port=8888,
    mode="listener",
    max=10.0,
    streamid="studio_a",
    enforced_encryption=true,
    passphrase=UPSTREAM_PASSWORD,
    on_connect=fun () -> log_event("studio_a", "connected"),
    on_disconnect=fun () -> log_event("studio_a", "disconnected")
  )

# Input for backup studio stream
studio_b =
  input.srt(
    id="studio_b",
    port=9999,
    mode="listener",
    max=10.0,
    streamid="studio_b",
    enforced_encryption=true,
    passphrase=UPSTREAM_PASSWORD,
    on_connect=fun () -> log_event("studio_b", "connected"),
    on_disconnect=fun () -> log_event("studio_b", "disconnected")
  )

# Log silence detection and resumption
studio_a =
  blank.detect(
    id="detect_studio_a",
    max_blank=MAX_BLANK,
    min_noise=MIN_NOISE,
    fun () ->
      log_event(
        "studio_a",
        "silence detected"
      ),
    on_noise=
      fun () ->
        log_event(
          "studio_a",
          "audio resumed"
        ),
    studio_a
  )

studio_b =
  blank.detect(
    id="detect_studio_b",
    max_blank=MAX_BLANK,
    min_noise=MIN_NOISE,
    fun () ->
      log_event(
        "studio_b",
        "silence detected"
      ),
    on_noise=
      fun () ->
        log_event(
          "studio_b",
          "audio resumed"
        ),
    studio_b
  )

# Consider inputs unavailable when silent
studio_a =
  blank.strip(
    id="stripped_studio_a", max_blank=MAX_BLANK, min_noise=MIN_NOISE, studio_a
  )
studio_b =
  blank.strip(
    id="stripped_studio_b", max_blank=MAX_BLANK, min_noise=MIN_NOISE, studio_b
  )

# Wrap it in a buffer to prevent latency from connection/disconnection to impact downstream operators/output
studio_a = buffer(id="buffered_studio_a", fallible=true, studio_a)
studio_b = buffer(id="buffered_studio_b", fallible=true, studio_b)

# Combine live inputs and fallback
radio =
  fallback(
    id="radio_prod", track_sensitive=false, [studio_a, studio_b, noodband]
  )

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

##############################################################################
#                             WARNING                                        #
#                       OUTPUTTING TO MULTIPLE                               #
#                          ICECAST SERVERS                                   #
#                                                                            #
# When outputting to multiple distinct Icecast servers, be aware that the    #
# instability of one server will affect all other streams. To ensure         #
# stability, each Icecast server output requires its own clock.              #
#                                                                            #
##############################################################################

# Create a clock for output to Icecast
audio_to_icecast = mksafe(buffer(radioproc))
clock.assign_new(id="icecast_clock", [audio_to_icecast])

# Create a clock for output to Dutch Media Exchange
audio_to_dme_a = mksafe(buffer(radioproc))
clock.assign_new(id="dme_a_clock", [audio_to_dme_a])

audio_to_dme_b = mksafe(buffer(radioproc))
clock.assign_new(id="dme_b_clock", [audio_to_dme_b])

# Create a clock for output to Radio Netwerk Nederland
audio_to_rnn = mksafe(buffer(radioproc))
clock.assign_new(id="rnn_clock", [audio_to_rnn])

# Function to output an icecast stream with common parameters
def output_icecast_stream(~format, ~description, ~mount, ~source) =
  output.icecast(
    format,
    fallible=false,
    host=ICECAST_SERVER,
    port=ICECAST_PORT,
    password=ICECAST_PASSWORD,
    name=ICECAST_NAME,
    description=description,
    mount=mount,
    source
  )
end

# Output a high bitrate mp3 stream
output_icecast_stream(
  format=%mp3(bitrate = 192, samplerate = 48000, internal_quality = 0),
  description=
    "Hoge Kwaliteit Stream (192kbit MP3)",
  mount=HIGH_QUALITY_MOUNT,
  source=audio_to_icecast
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
  source=audio_to_icecast
)

# Output a high bitrate AAC stream
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
  source=audio_to_icecast
)

# Output a high bitrate AAC stream to Dutch Media Exchange
output.icecast(
  %fdkaac(
    channels = 2,
    samplerate = 48000,
    bitrate = 576,
    afterburner = true,
    aot = 'mpeg4_aac_lc',
    transmux = 'adts',
    sbr_mode = true
  ),
  host=DME_INGEST_A_HOST,
  port=DME_INGEST_A_PORT,
  user=DME_INGEST_A_USER,
  password=DME_INGEST_A_PASSWORD,
  mount=DME_MOUNT,
  name=DME_NAME,
  description=DME_DESCRIPTION,
  audio_to_dme_a
)

output.icecast(
  %fdkaac(
    channels = 2,
    samplerate = 48000,
    bitrate = 576,
    afterburner = true,
    aot = 'mpeg4_aac_lc',
    transmux = 'adts',
    sbr_mode = true
  ),
  host=DME_INGEST_B_HOST,
  port=DME_INGEST_B_PORT,
  user=DME_INGEST_B_USER,
  password=DME_INGEST_B_PASSWORD,
  mount=DME_MOUNT,
  name=DME_NAME,
  description=DME_DESCRIPTION,
  audio_to_dme_b
)

# Feed the audio to ODR-AudioEnc
output.external(
  %wav(channels = 2, samplerate = 48000),
  "/bin/odr-audioenc -i - --bitrate=#{ODR_AUDIOENC_BITRATE} \
   --stats=/dabplus/sockets/dab_stats --edi='#{ODR_AUDIOENC_EDI_URL}'",
  audio_to_rnn
)

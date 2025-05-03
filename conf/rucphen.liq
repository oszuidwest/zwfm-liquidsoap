# Audio defaults
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Streaming configuration (do change this)
icecastserver = "icecast.zuidwest.cloud"
icecastport = 80
icecastpassword = "hackme"
fallbackfile = "/audio/fallback.mp3"
upstreampassword = "foxtrot-uniform-charlie-kilo"

# Logging function for various events
def log_event(input_name, event) =
  log(
    "#{input_name} #{event}",
    level=3
  )
end

# The noodband source file
noodband_file = source.drop.metadata(id="noodband_file", single(fallbackfile))
silence = blank()

# Get the current noodband source
def get_noodband_source() =
  use_noodband = ref(true)

  if
    file.exists(use_noodband_file)
  then
    x = file.contents(use_noodband_file)
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
    passphrase=upstreampassword,
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
    passphrase=upstreampassword,
    on_connect=fun () -> log_event("studio_b", "connected"),
    on_disconnect=fun () -> log_event("studio_b", "disconnected")
  )

# Log silence detection and resumption
studio_a =
  blank.detect(
    id="detect_studio_a",
    max_blank=15.0,
    min_noise=15.0,
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
    max_blank=15.0,
    min_noise=15.0,
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
  blank.strip(id="stripped_studio_a", max_blank=15., min_noise=15., studio_a)
studio_b =
  blank.strip(id="stripped_studio_b", max_blank=15., min_noise=15., studio_b)

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
    license_key=
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
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
audio_to_dme = mksafe(buffer(radioproc))
clock.assign_new(id="dme_clock", [audio_to_dme])

# Create a clock for output to Radio Netwerk Nederland
audio_to_rnn = mksafe(buffer(radioproc))
clock.assign_new(id="rnn_clock", [audio_to_rnn])

# Function to output an icecast stream with common parameters
def output_icecast_stream(~format, ~description, ~mount, ~source) =
  output.icecast(
    format,
    fallible=false,
    host=icecastserver,
    port=icecastport,
    password=icecastpassword,
    name=
      "Radio Rucphen",
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
  mount="/radiorucphen.mp3",
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
  mount="/radiorucphen.aac",
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
  mount="/radiorucphen.stl",
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
  host="xxxxxxx",
  port=0000,
  password="xxxxx",
  mount="/xxxx",
  name=
    "Rucphen RTV",
  description=
    "Altijd nieuws, altijd muziek",
  user="xxxx",
  audio_to_dme
)

# Feed the audio to ODR-AudioEnc
output.external(
  %wav(channels = 2, samplerate = 48000),
  "/bin/odr-audioenc -i - --bitrate=112 --stats=/dabplus/sockets/dab_stats \
   --edi='tcp://localhost:6000'",
  audio_to_rnn
)

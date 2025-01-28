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

# Backup file to be played when no audio is coming from the studio
noodband = source.drop.metadata(id="noodband", single(fallbackfile))

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
    preset="/var/cache/liquidsoap/.liquidsoap.rc",
    radio
  )

# Send processed audio to a dummy output since we only use it for MicroMPX
output.dummy(radioproc)

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
audio_to_icecast = mksafe(buffer(radio))
clock.assign_new(id="icecast_clock", [audio_to_icecast])

# Function to output an icecast stream with common parameters
def output_icecast_stream(~format, ~description, ~mount, ~source) =
  output.icecast(
    format,
    fallible=false,
    host=icecastserver,
    port=icecastport,
    password=icecastpassword,
    name=
      "ZuidWest FM",
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
  mount="/zuidwest.mp3",
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
  mount="/zuidwest.aac",
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
  mount="/zuidwest.stl",
  source=audio_to_icecast
)

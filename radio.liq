# Log (should not be changed)
settings.log.file.path := "/var/log/liquidsoap/<script>.log"

# Audio defaults
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Streaming configuration (do change this)
icecastserver = "icecast.example.org"
icecastport = 8000
icecastpassword = "hackme"
fallbackfile = "/var/audio/fallback.ogg"
upstreampassword = "foxtrot-uniform-charlie-kilo"

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
    passphrase=upstreampassword
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
    passphrase=upstreampassword
  )

# Consider inputs unavailable when silent
studio_a = blank.strip(id="stripped_studio_a", max_blank=10., min_noise=30., studio_a)
studio_b = blank.strip(id="stripped_studio_b", max_blank=10., min_noise=30., studio_b)

# Wrap it in a buffer to prevent latency from connection/disconnection to impact downstream operators/output
studio_a = buffer(id="buffered_studio", fallible=true, studio_a)
studio_b = buffer(id="buffered_studiobackup", fallible=true, studio_b)

# Combine live inputs and fallback
radio = fallback(id="radio_prod", track_sensitive=false, [studio_a, studio_b, noodband])

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

# StereoTool implementation
radioproc =
  stereotool(
    library_file="/opt/stereotool/st_plugin.so",
    license_key=
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    preset="/etc/liquidsoap/st.ini",
    radio
  )

# Output StereoTool sound to a dummy output since we only use it for MicroMPX
output.dummy(radioproc)

# Output a high bitrate mp3 stream
output_icecast_stream(
  format=%mp3(bitrate = 192, samplerate = 48000, internal_quality = 0),
  description=
    "Hoge Kwaliteit Stream (192kbit MP3)",
  mount="/zuidwest.mp3",
  source=radio
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
  source=radio
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
  source=radio
)

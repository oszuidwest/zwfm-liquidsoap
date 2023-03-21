# Daemon configuration (should not be changed)
settings.init.daemon.change_user.set(true)
settings.init.daemon.change_user.group.set("liquidsoap")
settings.init.daemon.change_user.user.set("liquidsoap")
settings.init.daemon.pidfile.path.set("/dev/null")

# General configuration (do change this)
icecastserver = "icecast.example.org"
icecastport = 8000
icecastpassword = "changeme"
fallbackfile = "/var/audio/fallback.ogg"
upstreampassword = "foxtrot-uniform-charlie-kilo"

# Fallback if there is no audio coming from the studio
noodband = drop_metadata(single(fallbackfile))

# Input for the studio stream
studio = input.srt(id="studio", port=9000, mode="listener", max=2.0, streamid="studio", passphrase=upstreampassword)

# Combine fallback and live input
radio = fallback(track_sensitive=false, [ blank.strip(max_blank=15.,min_noise=30.,studio), noodband ])

# Pipe the final mix trough StereoTool
radioproc = pipe(process='/bin/stereotool - - -w 8888 -q -k "<xxxxxxxxx>" -s /etc/liquidsoap/st.ini', radio)

# Output configuration
output_config = (
  fallible=true,
  host=icecastserver,
  port=icecastport,
  password=icecastpassword,
  name='ZuidWest FM',
  radio
)

# Output a lossless ogg/flac stream
output.icecast(%ogg(%flac), description='Studio to Transmitter (ongecomprimeerde audio)', mount='/zuidwest.stl', output_config)

# Output a high bitrate mp3 stream
output.icecast(%mp3(bitrate=192,samplerate=48000), description='Hoge Kwaliteit Stream (192kbit MP3)', mount='/zuidwest.mp3', output_config)

# Output a low bitrate AAC stream
output.icecast(%fdkaac(channels=2, samplerate=48000, bitrate=96, afterburner=true, aot='mpeg4_aac_lc', transmux='adts', sbr_mode=true), description='Mobile Stream (96kbit AAC)', mount='/zuidwest.aac', output_config)

# Output both mixes as dummy too, to be sure
output.dummy(fallible=true, radioproc)
output.dummy(fallible=true, radio)

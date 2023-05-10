# Daemon configuration (should not be changed)
set("init.daemon.change_user", true)
set("init.daemon.change_user.group", "liquidsoap")
set("init.daemon.change_user.user", "liquidsoap")
set("init.daemon.pidfile.path", "/dev/null")
set("log.file", true)
set("log.level", 4)
set("log.file.path", "/var/log/liquidsoap/<script>.log")

# Prometheus configuration (should not be changed)
set("prometheus.server", true)
set("prometheus.server.port", 9090)


# General configuration (do change this)

## Input configuration
upstreampassword = "foxtrot-uniform-charlie-kilo"

# Stereotool configuration
stereotoolport = 9000

# Output configuration
icecastserver = "icecast.example.org"
icecastport = 8000
icecastpassword = "changeme"

# General configuration
fallbackfile = "/var/audio/fallback.ogg"



# Fallback if there is no audio coming from the studio
emergency_loop = drop_metadata(single(fallbackfile))

# Input port for the studio stream
studio = drop_metadata(input.harbor('studio',port=8080,buffer=8.,max=20.,password=upstreampassword))

# Insert silence when there is no data from input
studio = mksafe(studio)

# Combine fallback and live input
radio = fallback(track_sensitive=false, [ blank.strip(max_blank=15.,min_noise=30.,studio), emergency_loop ])

# Output a high quality ogg/flac stream
output.icecast(%ogg(%flac),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.stl', name='ZuidWest FM', description='Studio to Transmitter (uncompressed audio)', radio)

# Output a high quality mp3 stream
output.icecast(%mp3(bitrate=192,samplerate=48000),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.mp3', name='ZuidWest FM', description='High Quality Stream (192kbit MP3)', radio)

# Output a low quality HE-AACv2 stream
output.icecast(%fdkaac(channels=2, samplerate=48000, bitrate=96, afterburner=true, aot='mpeg4_aac_lc', transmux='adts', sbr_mode=true),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.aac', name='ZuidWest FM', description='Mobile Stream (96kbit AAC)', radio)

# Feed the audio to StereoTool too, which can generate MicroMPX
output.external(%wav, reopen_on_error=true, "#{'/opt/stereotool/stereotool - /dev/null -w '}#{stereotoolport}#{' -q -s /etc/liquidsoap/st.ini'}", radio)

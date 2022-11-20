# Daemon configuration (should not be changed)
settings.init.daemon.change_user.set(true)
settings.init.daemon.change_user.group.set("liquidsoap")
settings.init.daemon.change_user.user.set("liquidsoap")
settings.init.daemon.pidfile.path.set("/dev/null")

# General configuration (do change this)
icecastserver = icecast.example.org
icecastport = 8000
icecastpassword = changeme
fallbackfile = /var/audio/fallback.ogg

# Fallback if there is no audio coming from the studio
noodband = drop_metadata(single('fallbackfile'))

# Input port for the studio stream
studio = drop_metadata(input.harbor('studio',port=8080,buffer=8.,max=20.,password='---'))

# Combine fallback and live input
radio = fallback (track_sensitive=false, [ strip_blank(max_blank=15.,min_noise=30.,studio), noodband ])

# Output a high quality ogg/flac stream
output.icecast(%ogg(%flac),fallible=true,
  host='localhost', port=80, password='---', mount='/zuidwest.stl', name='ZuidWest FM', description='Studio to Transmitter (ongecomprimeerde audio)', radio)

# Output a high quality mp3 stream
output.icecast(%mp3(bitrate=192,samplerate=48000),fallible=true,
  host='localhost', port=80, password='---', mount='/zuidwest.mp3', name='ZuidWest FM', description='Hoge Kwaliteit Stream (192kbit MP3)', radio)

# Output a low quality HE-AAC v2 stream
output.icecast(%fdkaac(channels=2, samplerate=48000, bitrate=64, afterburner=false, aot='mpeg4_he_aac_v2', transmux='adts', sbr_mode=false),fallible=true,
  host='localhost', port=80, password='---', mount='/zuidwest.aac', name='ZuidWest FM', description='Mobile Stream (64kbit HE-AAC v2)', radio)

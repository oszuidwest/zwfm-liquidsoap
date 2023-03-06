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
upstreampassword = "foxtrotuniformcharliekilo"

# Define functions for connection and disconnects
def log_disconnect () =
     process.run("/etc/liquidsoap/harbor_log.sh disconnect /tmp/harborlog.txt")
end

def log_connect (header) =
     process.run("/etc/liquidsoap/harbor_log.sh connect /tmp/harborlog.txt")
     log("We need to specify a header so here it is - #{header}")
end

# Fallback if there is no audio coming from the studio
noodband = drop_metadata(single(fallbackfile))

# Input port for the studio stream
studio = drop_metadata(input.harbor('studio',port=8080,buffer=8.,max=20.,password=upstreampassword, on_disconnect=log_disconnect, on_connect=log_connect))

# Insert silence when there is no data from input
studio = mksafe(studio)

# Combine fallback and live input
radio = fallback(track_sensitive=false, [ blank.strip(max_blank=15.,min_noise=30.,studio), noodband ])

# Output a high quality ogg/flac stream
output.icecast(%ogg(%flac),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.stl', name='ZuidWest FM', description='Studio to Transmitter (ongecomprimeerde audio)', radio)

# Output a high quality mp3 stream
output.icecast(%mp3(bitrate=192,samplerate=48000),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.mp3', name='ZuidWest FM', description='Hoge Kwaliteit Stream (192kbit MP3)', radio)

# Output a low quality HE-AACv2 stream
output.icecast(%fdkaac(channels=2, samplerate=48000, bitrate=96, afterburner=true, aot='mpeg4_aac_lc', transmux='adts', sbr_mode=true),fallible=true,
  host=icecastserver, port=icecastport, password=icecastpassword, mount='/zuidwest.aac', name='ZuidWest FM', description='Mobile Stream (96kbit AAC)', radio)
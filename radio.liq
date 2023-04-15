# Daemon configuration (should not be changed)
set("init.daemon.change_user.set", true)
set("init.daemon.change_user.group", "liquidsoap")
set("init.daemon.change_user.user", "liquidsoap")
set("init.daemon.pidfile.path", "/run/liquidsoap-radio.pid")
set("log.file.path", "/var/log/liquidsoap/<script>.log")

# General configuration (do change this)
icecastserver = "icecast.example.org"
icecastport = 8000
icecastpassword = "hackme"
fallbackfile = "/var/audio/fallback.ogg"
upstreampassword = "foxtrot-uniform-charlie-kilo"

# Fallback if there is no audio coming from the studio
noodband = drop_metadata(single(fallbackfile))

# Input for the studio stream
studio = input.srt(id="studio", port=9000, mode="listener", max=2.0, passphrase=upstreampassword)

# Insert silence when there is no data from input
# studio = mksafe(studio) # This causes the ogg/flac stream to disconnect when switching between the fallback and studio?

# Wrap it in a buffer to prevent latency from connection/disconnection to impact downstream operators/output
studio = buffer(fallible=true, studio)

# Combine fallback and live input
radio = fallback(track_sensitive=false, [ blank.strip(max_blank=15.,min_noise=30.,studio), noodband ])

# Function to output an icecast stream with common parameters
def output_icecast_stream(~format, ~description, ~mount, ~source) =
  output.icecast(
    format,
    fallible=false,
    host=icecastserver,
    port=icecastport,
    password=icecastpassword,
    name="ZuidWest FM",
    description=description,
    mount=mount,
    source
  )
end

# Output a lossless ogg/flac stream
output_icecast_stream(format=%ogg(%flac), description="Studio to Transmitter (ongecomprimeerde audio)", mount="/zuidwest.stl", source=radio)

# Output a high bitrate mp3 stream
output_icecast_stream(format=%mp3(bitrate=192, samplerate=48000), description="Hoge Kwaliteit Stream (192kbit MP3)", mount="/zuidwest.mp3", source=radio)

# Output a low bitrate AAC stream
output_icecast_stream(format=%fdkaac(channels=2, samplerate=48000, bitrate=96, afterburner=true, aot='mpeg4_aac_lc', transmux='adts', sbr_mode=true), description="Mobile Stream (96kbit AAC)", mount="/zuidwest.aac", source=radio)

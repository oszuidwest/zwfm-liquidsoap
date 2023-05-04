# Daemon configuration (should not be changed)
settings.init.daemon.change_user.set(true)
settings.init.daemon.change_user.group.set("liquidsoap")
settings.init.daemon.change_user.user.set("liquidsoap")
settings.init.daemon.pidfile.path.set("/dev/null")

# Prometheus configuration (should not be changed)
if getenv("PROMETHEUS_ENABLED") == "true" then
  settings.prometheus.server.set(true)
  settings.prometheus.server.port.set(9090)
end

# Define default values for environment variables

# Set environments if empty

# Source Configuration
if getenv("SOURCE_PASSWORD") == "" then
    setenv("SOURCE_PASSWORD", "foxtrot-uniform-charlie-kilo")
end

if getenv("SOURCE_TYPE") == "" then
    setenv("SOURCE_TYPE", "icecast")
end
if getenv("SOURCE_PORT") == "" then
    setenv("SOURCE_PORT", "8080")
end


if getenv("ICECAST_SERVER_ADDRESS") == "" then
    setenv("ICECAST_SERVER_ADDRESS", "icecast.example.org")
end
if getenv("ICECAST_SERVER_PORT") == "" then
    setenv("ICECAST_SERVER_PORT", "8000")
end
if getenv("ICECAST_SERVER_PASSWORD") == "" then
    setenv("ICECAST_SERVER_PASSWORD", "changeme")
end

# STL Stream
if getenv("ICECAST_STL_ENABLED") == "" then
    setenv("ICECAST_STL_ENABLED", "false")
end
if getenv("ICECAST_STL_NAME") == "" then
    setenv("ICECAST_STL_NAME", "ZuidWest FM")
end
if getenv("ICECAST_STL_DESC") == "" then
    setenv("ICECAST_STL_DESC", "Studio to Transmitter (uncompressed audio)")
end
if getenv("ICECAST_STL_MOUNTPOINT") == "" then
    setenv("ICECAST_STL_MOUNTPOINT", "/zuidwest.stl")
end

# High Quality MP3 Stream
if getenv("ICECAST_HQ_ENABLED") == "" then
    setenv("ICECAST_HQ_ENABLED", "false")
end
if getenv("ICECAST_HQ_NAME") == "" then
    setenv("ICECAST_HQ_NAME", "ZuidWest FM")
end
if getenv("ICECAST_HQ_DESC") == "" then
    setenv("ICECAST_HQ_DESC", "High Quality Stream (192kbit MP3)")
end
if getenv("ICECAST_HQ_MOUNTPOINT") == "" then
    setenv("ICECAST_HQ_MOUNTPOINT", "/zuidwest.mp3")
end

# Low Quality AAC Stream
if getenv("ICECAST_LQ_ENABLED") == "" then
    setenv("ICECAST_LQ_ENABLED", "false")
end
if getenv("ICECAST_LQ_NAME") == "" then
    setenv("ICECAST_LQ_NAME", "ZuidWest FM")
end
if getenv("ICECAST_LQ_DESC") == "" then
    setenv("ICECAST_LQ_DESC", "Mobile Stream (96kbit AAC)")
end
if getenv("ICECAST_LQ_MOUNTPOINT") == "" then
    setenv("ICECAST_LQ_MOUNTPOINT", "/zuidwest.aac")
end

# Stereotool Config
if getenv("STEREOTOOL_ENABLED") == "" then
    setenv("STEREOTOOL_ENABLED", "false")
end

if getenv("STEREOTOOL_PORT") == "" then
    setenv("STEREOTOOL_PORT", "9000")
end

# Fallback Configuration
if getenv("FALLBACK_FILE") == "" then
    setenv("FALLBACK_FILE", "/var/audio/fallback.ogg")
end




# Fallback if there is no audio coming from the studio
emergency_loop = drop_metadata(single(fallbackfile))

if getenv("SOURCE_TYPE") == "srt" then
  # Input for the studio stream based on SRT
  studio = input.srt(
    id="studio",
    port=getenv("SOURCE_PORT"),
    mode="listener",
    max=2.0,
    streamid=getenv("SOURCE_PASSWORD"),
    passphrase=getenv("SOURCE_PASSWORD")
  )
else 
  # Input for the studio stream based on the Icecast Protocol
  studio = drop_metadata(
    input.harbor(
      'studio',
      port=getenv("SOURCE_PORT"),
      buffer=8.,
      max=20.,
      password=getenv("SOURCE_PASSWORD")
    )
  )
end

# Insert silence when there is no data from input
studio = mksafe(studio)

# Combine fallback and live input
radio = fallback(
  track_sensitive=false,
  [ 
    blank.strip( 
      max_blank=15.,
      min_noise=30.,
      studio
    ),
    emergency_loop 
  ]
)

# Output a high quality ogg/flac stream
if getenv("ICECAST_STL_ENABLED") == "true" then
  output.icecast(
    %ogg(
      %flac
    ),
    fallible=true,
    host=getenv("ICECAST_SERVER_ADDRESS"),
    port=getenv("ICECAST_SERVER_PORT"),
    password=getenv("ICECAST_SERVER_PASSWORD"),
    mount=getenv("ICECAST_STL_MOUNTPOINT"),
    name=getenv("ICECAST_STL_NAME"),
    description=getenv("ICECAST_STL_DESC"),
    radio
  )
end

# Output a high quality mp3 stream
if getenv("ICECAST_HQ_ENABLED") == "true" then
  output.icecast(
    %mp3(
      bitrate=192,
      samplerate=48000
    ),
    fallible=true,
    host=getenv("ICECAST_SERVER_ADDRESS"),
    port=getenv("ICECAST_SERVER_PORT"),
    password=getenv("ICECAST_SERVER_PASSWORD"),
    mount=getenv("ICECAST_HQ_MOUNTPOINT"),
    name=getenv("ICECAST_HQ_NAME"),
    description=getenv("ICECAST_HQ_DESC"),
    radio
  )
end

# Output a low quality HE-AACv2 stream
if getenv("ICECAST_LQ_ENABLED") == "true" then
  output.icecast(
    %fdkaac(
      channels=2,
      samplerate=48000,
      bitrate=96,
      afterburner=true,
      aot='mpeg4_aac_lc',
      transmux='adts',
      sbr_mode=true
    ),
    fallible=true,
    host=getenv("ICECAST_SERVER_ADDRESS"),
    port=getenv("ICECAST_SERVER_PORT"),
    password=getenv("ICECAST_SERVER_PASSWORD"),
    mount=getenv("ICECAST_LQ_MOUNTPOINT"),
    name=getenv("ICECAST_LQ_NAME"),
    description=getenv("ICECAST_LQ_DESC"),
    radio
)
end

# Feed the audio to StereoTool too, which can generate MicroMPX
if getenv("STEREOTOOL_ENABLED") == "true" then
  output.external(
    %wav(
      channels=2,
      samplerate=48000
    ),
    reopen_on_error=true,
    "#{'/opt/stereotool/stereotool - /dev/null -w '}#{stereotoolport}#{' -q -s /etc/liquidsoap/st.ini'}",
    radio
  )
end

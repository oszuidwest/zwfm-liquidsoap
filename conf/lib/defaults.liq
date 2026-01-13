# Default configuration values - common for all stations
# DO NOT EDIT THESE VALUES HERE - Set them in your .env file instead!

# Production settings
settings.ffmpeg.log.verbosity := "warning"
settings.clock.max_latency := 60.0

# Server socket for runtime control (access via: socat /tmp/liquidsoap.sock -)
SERVER_SOCKET_ENABLED =
  environment.get("SERVER_SOCKET_ENABLED", default="false") == "true"
SERVER_SOCKET_PATH =
  environment.get("SERVER_SOCKET_PATH", default="/tmp/liquidsoap.sock")

if
  SERVER_SOCKET_ENABLED
then
  settings.server.socket := true
  settings.server.socket.path := SERVER_SOCKET_PATH
  log(
    "Server socket enabled at #{SERVER_SOCKET_PATH}",
    level=3
  )
end

# Audio settings
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Station configuration
# These MUST be set in your .env file - no defaults provided
STATION_ID = string.case(environment.get("STATION_ID"), lower=true)
STATION_NAME = environment.get("STATION_NAME")

# Icecast server configuration
# These MUST be set in your .env file - no defaults provided
ICECAST_HOST = environment.get("ICECAST_HOST")
ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT"))
ICECAST_SOURCE_PASSWORD = environment.get("ICECAST_SOURCE_PASSWORD")

# Icecast mount points
# Default mount point is based on station ID
# Override these in .env if needed
ICECAST_MOUNT_BASE = environment.get("ICECAST_MOUNT_BASE", default=STATION_ID)
ICECAST_MOUNT_MP3 =
  environment.get("ICECAST_MOUNT_MP3", default="/#{ICECAST_MOUNT_BASE}.mp3")
ICECAST_MOUNT_AAC_LOW =
  environment.get("ICECAST_MOUNT_AAC_LOW", default="/#{ICECAST_MOUNT_BASE}.aac")
ICECAST_MOUNT_AAC_HIGH =
  environment.get(
    "ICECAST_MOUNT_AAC_HIGH",
    default="/#{ICECAST_MOUNT_BASE}.stl"
  )

# Icecast stream bitrates
# Override these in .env if needed
ICECAST_BITRATE_MP3 =
  int_of_string(environment.get("ICECAST_BITRATE_MP3", default="192"))
ICECAST_BITRATE_AAC_LOW =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_LOW", default="96"))
ICECAST_BITRATE_AAC_HIGH =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_HIGH", default="576"))

# SRT studio input ports
# Override these in .env if needed
SRT_PORT_PRIMARY =
  int_of_string(environment.get("SRT_PORT_PRIMARY", default="8888"))
SRT_PORT_SECONDARY =
  int_of_string(environment.get("SRT_PORT_SECONDARY", default="9999"))

# DAB+ configuration (optional)
# Only set these if you want DAB+ output
DAB_BITRATE = environment.get("DAB_BITRATE", default="")
DAB_EDI_DESTINATIONS = environment.get("DAB_EDI_DESTINATIONS", default="")
DAB_METADATA_SOCKET = environment.get("DAB_METADATA_SOCKET", default="")

# PAD size in bytes (0-196) - only used when PAD socket is configured
DAB_METADATA_SIZE = environment.get("DAB_METADATA_SIZE", default="")

# Silence detection configuration
# These have sensible defaults but can be overridden in .env
SILENCE_SWITCH_SECONDS =
  float_of_string(environment.get("SILENCE_SWITCH_SECONDS", default="15.0"))
AUDIO_VALID_SECONDS =
  float_of_string(environment.get("AUDIO_VALID_SECONDS", default="15.0"))
SILENCE_THRESHOLD =
  float_of_string(environment.get("SILENCE_THRESHOLD", default="-40.0"))

# Common file paths
# These have sensible defaults but can be overridden in .env
EMERGENCY_AUDIO_PATH =
  environment.get("EMERGENCY_AUDIO_PATH", default="/audio/fallback.ogg")
SILENCE_CONTROL_PATH =
  environment.get("SILENCE_CONTROL_PATH", default="/silence_detection.txt")

# Logging function for various events
def log_event(input_name, event) =
  log(
    "#{input_name} #{event}",
    level=3
  )
end

# Track the last known silence detection state
silence_detection_state = ref(true)

# Function to check if silence detection is enabled
def is_silence_detection_enabled() =
  current_state =
    if
      file.exists(SILENCE_CONTROL_PATH)
    then
      file_content = file.contents(SILENCE_CONTROL_PATH)
      first_char = list.hd(string.chars(file_content))
      first_char == "1"
    else
      # Default to enabled if file doesn't exist
      true
    end

  # Log if state has changed
  if
    current_state != silence_detection_state()
  then
    silence_detection_state := current_state
    if
      current_state
    then
      log(
        "Silence detection ENABLED",
        level=3
      )
    else
      log(
        "Silence detection DISABLED",
        level=3
      )
    end
  end

  current_state
end

# Create fallback source - either from file or blank audio
fallback_file =
  if
    file.exists(EMERGENCY_AUDIO_PATH)
  then
    source.drop.metadata(id="fallback_file", single(EMERGENCY_AUDIO_PATH))
  else
    blank(id="fallback_blank")
  end

# Create blank fallback source
fallback_blank = blank(id="fallback_disabled")

# Use switch to select between fallback sources based on silence detection state
emergency_fallback =
  switch(
    id="switch_fallback",
    track_sensitive=false,
    [({is_silence_detection_enabled()}, fallback_file), ({true}, fallback_blank)
    ]
  )

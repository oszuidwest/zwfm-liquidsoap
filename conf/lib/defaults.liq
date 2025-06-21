# Default configuration values - common for all stations
# DO NOT EDIT THESE VALUES HERE - Set them in your .env file instead!

# Audio settings
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Station configuration
# These MUST be set in your .env file - no defaults provided
STATION_NAME_SHORT = environment.get("STATION_NAME_SHORT")
STATION_NAME_FULL = environment.get("STATION_NAME_FULL")

# Icecast server configuration
# These MUST be set in your .env file - no defaults provided
ICECAST_SERVER = environment.get("ICECAST_SERVER")
ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT"))
ICECAST_PASSWORD = environment.get("ICECAST_PASSWORD")

# Icecast mount points
# Default mount point is lowercase station short name (e.g., "zuidwest" or "rucphen")
# Override these in .env if needed
ICECAST_MOUNTPOINT =
  environment.get(
    "ICECAST_MOUNTPOINT", default=string.case(STATION_NAME_SHORT, lower=true)
  )
HIGH_QUALITY_MOUNT =
  environment.get("HIGH_QUALITY_MOUNT", default="/#{ICECAST_MOUNTPOINT}.mp3")
MOBILE_MOUNT =
  environment.get("MOBILE_MOUNT", default="/#{ICECAST_MOUNTPOINT}.aac")
TRANSPORT_MOUNT =
  environment.get("TRANSPORT_MOUNT", default="/#{ICECAST_MOUNTPOINT}.stl")

# ODR-AudioEnc configuration for DAB+ (optional)
# Only set these if you want DAB+ output
ODR_AUDIOENC_BITRATE = environment.get("ODR_AUDIOENC_BITRATE", default="")
ODR_AUDIOENC_EDI_URL = environment.get("ODR_AUDIOENC_EDI_URL", default="")
ODR_PADENC_SOCK = environment.get("ODR_PADENC_SOCK", default="")

# Silence detection configuration
# These have sensible defaults but can be overridden in .env
MAX_BLANK = float_of_string(environment.get("MAX_BLANK", default="15.0"))
MIN_NOISE = float_of_string(environment.get("MIN_NOISE", default="15.0"))

# Common file paths
# These have sensible defaults but can be overridden in .env
FALLBACK_FILE = environment.get("FALLBACK_FILE", default="/audio/fallback.ogg")
SILENCE_DETECTION_FILE =
  environment.get("SILENCE_DETECTION_FILE", default="/silence_detection.txt")

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
      file.exists(SILENCE_DETECTION_FILE)
    then
      file_content = file.contents(SILENCE_DETECTION_FILE)
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
    file.exists(FALLBACK_FILE)
  then
    source.drop.metadata(id="fallback_file", single(FALLBACK_FILE))
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

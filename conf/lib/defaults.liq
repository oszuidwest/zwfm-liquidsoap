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

# ODR-AudioEnc configuration for DAB+
# These MUST be set in your .env file - no defaults provided
ODR_AUDIOENC_BITRATE = int_of_string(environment.get("ODR_AUDIOENC_BITRATE"))
ODR_AUDIOENC_EDI_URL = environment.get("ODR_AUDIOENC_EDI_URL")

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

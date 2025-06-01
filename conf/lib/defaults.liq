# Default configuration values - common for all stations

# Audio settings
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Silence detection defaults
MAX_BLANK = float_of_string(environment.get("MAX_BLANK", default="15.0"))
MIN_NOISE = float_of_string(environment.get("MIN_NOISE", default="15.0"))

# Common file paths
FALLBACK_FILE = environment.get("FALLBACK_FILE", default="/audio/fallback.mp3")
USE_NOODBAND_FILE = environment.get("USE_NOODBAND_FILE", default="/use_noodband.txt")

# Logging function for various events
def log_event(input_name, event) =
  log(
    "#{input_name} #{event}",
    level=3
  )
end

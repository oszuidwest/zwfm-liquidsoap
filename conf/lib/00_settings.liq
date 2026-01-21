# Settings and environment configuration
# This file contains ONLY settings and environment variables - no logic or functions

# Liquidsoap engine settings
settings.ffmpeg.log.verbosity := "warning"
settings.clock.max_latency := 60.0
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Station identity (REQUIRED - no defaults)
STATION_ID = string.case(environment.get("STATION_ID"), lower=true)
STATION_NAME = environment.get("STATION_NAME")

# Icecast server configuration (REQUIRED - no defaults)
ICECAST_HOST = environment.get("ICECAST_HOST")
ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT"))
ICECAST_SOURCE_PASSWORD = environment.get("ICECAST_SOURCE_PASSWORD")

# Icecast mount points (default based on station ID)
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

# Icecast stream bitrates (kbps)
ICECAST_BITRATE_MP3 =
  int_of_string(environment.get("ICECAST_BITRATE_MP3", default="192"))
ICECAST_BITRATE_AAC_LOW =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_LOW", default="96"))
ICECAST_BITRATE_AAC_HIGH =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_HIGH", default="576"))

# SRT studio input configuration
SRT_PASSPHRASE = environment.get("SRT_PASSPHRASE")
SRT_PORT_PRIMARY =
  int_of_string(environment.get("SRT_PORT_PRIMARY", default="8888"))
SRT_PORT_SECONDARY =
  int_of_string(environment.get("SRT_PORT_SECONDARY", default="9999"))

# Silence detection configuration
SILENCE_SWITCH_SECONDS =
  float_of_string(environment.get("SILENCE_SWITCH_SECONDS", default="15.0"))
AUDIO_VALID_SECONDS =
  float_of_string(environment.get("AUDIO_VALID_SECONDS", default="15.0"))
SILENCE_THRESHOLD =
  float_of_string(environment.get("SILENCE_THRESHOLD", default="-40.0"))

# Emergency fallback audio path
EMERGENCY_AUDIO_PATH =
  environment.get("EMERGENCY_AUDIO_PATH", default="/audio/fallback.ogg")

# DAB+ configuration (optional - both required to enable)
DAB_BITRATE = environment.get("DAB_BITRATE", default="")
DAB_EDI_DESTINATIONS = environment.get("DAB_EDI_DESTINATIONS", default="")
DAB_METADATA_SOCKET = environment.get("DAB_METADATA_SOCKET", default="")
DAB_METADATA_SIZE = environment.get("DAB_METADATA_SIZE", default="")

# StereoTool configuration (optional)
STEREOTOOL_LICENSE = environment.get("STEREOTOOL_LICENSE", default="")

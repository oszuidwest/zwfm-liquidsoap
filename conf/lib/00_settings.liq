# Settings and environment configuration
# This file contains ONLY settings and environment variables - no logic or functions

# Liquidsoap engine settings
settings.ffmpeg.log.verbosity := "warning"
settings.clock.max_latency := 60.0
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

# Station identity (REQUIRED - no defaults)
let STATION_ID = string.case(environment.get("STATION_ID"), lower=true)
let STATION_NAME = environment.get("STATION_NAME")

# Icecast server configuration (REQUIRED - no defaults)
let ICECAST_HOST = environment.get("ICECAST_HOST")
let ICECAST_PORT = int_of_string(environment.get("ICECAST_PORT"))
let ICECAST_SOURCE_PASSWORD = environment.get("ICECAST_SOURCE_PASSWORD")

# Icecast mount points (default based on station ID)
let ICECAST_MOUNT_BASE =
  environment.get("ICECAST_MOUNT_BASE", default=STATION_ID)
let ICECAST_MOUNT_MP3 =
  environment.get("ICECAST_MOUNT_MP3", default="/#{ICECAST_MOUNT_BASE}.mp3")
let ICECAST_MOUNT_AAC_LOW =
  environment.get("ICECAST_MOUNT_AAC_LOW", default="/#{ICECAST_MOUNT_BASE}.aac")
let ICECAST_MOUNT_AAC_HIGH =
  environment.get(
    "ICECAST_MOUNT_AAC_HIGH",
    default="/#{ICECAST_MOUNT_BASE}.stl"
  )

# Icecast stream bitrates (kbps)
let ICECAST_BITRATE_MP3 =
  int_of_string(environment.get("ICECAST_BITRATE_MP3", default="192"))
let ICECAST_BITRATE_AAC_LOW =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_LOW", default="96"))
let ICECAST_BITRATE_AAC_HIGH =
  int_of_string(environment.get("ICECAST_BITRATE_AAC_HIGH", default="576"))

# SRT studio input configuration
let SRT_PASSPHRASE = environment.get("SRT_PASSPHRASE")
let SRT_PORT_PRIMARY =
  int_of_string(environment.get("SRT_PORT_PRIMARY", default="8888"))
let SRT_PORT_SECONDARY =
  int_of_string(environment.get("SRT_PORT_SECONDARY", default="9999"))

# Silence detection configuration
let SILENCE_SWITCH_SECONDS =
  float_of_string(environment.get("SILENCE_SWITCH_SECONDS", default="15.0"))
let AUDIO_VALID_SECONDS =
  float_of_string(environment.get("AUDIO_VALID_SECONDS", default="15.0"))
let SILENCE_THRESHOLD =
  float_of_string(environment.get("SILENCE_THRESHOLD", default="-40.0"))

# Emergency fallback audio path
let EMERGENCY_AUDIO_PATH =
  environment.get("EMERGENCY_AUDIO_PATH", default="/audio/fallback.ogg")

# Opt-in silent fallback when the emergency audio file is unusable
# (development/testing only)
let EMERGENCY_ALLOW_BLANK =
  environment.get("EMERGENCY_ALLOW_BLANK", default="false") == "true"

# DAB+ configuration (optional - both required to enable)
let DAB_BITRATE = environment.get("DAB_BITRATE", default="")
let DAB_EDI_DESTINATIONS = environment.get("DAB_EDI_DESTINATIONS", default="")
let DAB_METADATA_SOCKET = environment.get("DAB_METADATA_SOCKET", default="")
let DAB_METADATA_SIZE = environment.get("DAB_METADATA_SIZE", default="")
let DAB_ACK_MONITOR_ENABLED =
  environment.get("DAB_ACK_MONITOR_ENABLED", default="true") == "true"
let DAB_ACK_POLL_SECONDS =
  float_of_string(environment.get("DAB_ACK_POLL_SECONDS", default="1.0"))
let DAB_ACK_WARN_SECONDS =
  int_of_string(environment.get("DAB_ACK_WARN_SECONDS", default="5"))
let DAB_ACK_DOWN_SECONDS =
  int_of_string(environment.get("DAB_ACK_DOWN_SECONDS", default="15"))
let DAB_ACK_STARTUP_GRACE_SECONDS =
  int_of_string(environment.get("DAB_ACK_STARTUP_GRACE_SECONDS", default="10"))

# HLS configuration (optional - storage zone and access key required to enable)
let HLS_BUNNY_STORAGE_ZONE =
  environment.get("HLS_BUNNY_STORAGE_ZONE", default="")
let HLS_BUNNY_ACCESS_KEY = environment.get("HLS_BUNNY_ACCESS_KEY", default="")
let HLS_BUNNY_ENDPOINT =
  environment.get("HLS_BUNNY_ENDPOINT", default="storage.bunnycdn.com")
let HLS_DIR = environment.get("HLS_DIR", default="/hls")
let HLS_BITRATE_LOW =
  int_of_string(environment.get("HLS_BITRATE_LOW", default="48"))
let HLS_BITRATE_MID =
  int_of_string(environment.get("HLS_BITRATE_MID", default="96"))
let HLS_BITRATE_HIGH =
  int_of_string(environment.get("HLS_BITRATE_HIGH", default="192"))
let HLS_SEGMENT_DURATION =
  float_of_string(environment.get("HLS_SEGMENT_DURATION", default="4.0"))
let HLS_SEGMENTS = int_of_string(environment.get("HLS_SEGMENTS", default="10"))
let HLS_SEGMENTS_OVERHEAD =
  int_of_string(environment.get("HLS_SEGMENTS_OVERHEAD", default="5"))

# Stream metadata endpoint (optional - bearer token required to enable)
let STREAM_METADATA_PORT =
  int_of_string(environment.get("STREAM_METADATA_PORT", default="7000"))
let STREAM_METADATA_BEARER_TOKEN =
  environment.get("STREAM_METADATA_BEARER_TOKEN", default="")

# StereoTool configuration (optional)
let STEREOTOOL_LICENSE = environment.get("STEREOTOOL_LICENSE", default="")

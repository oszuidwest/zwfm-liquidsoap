# Minimal settings required to exercise Icecast output health registration.
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

let ICECAST_HOST = "127.0.0.1"
let ICECAST_PORT = 65534
let ICECAST_SOURCE_PASSWORD = "test"
let STATION_NAME =
  "Test Station"

%include "../conf/lib/60_output_icecast.liq"

output_icecast_stream(
  format=%ffmpeg(
    format = "mp3",
    %audio(codec = "libmp3lame", b = "64k", ar = 48000, ac = 2)
  ),
  description="Test stream",
  mount="/test.mp3",
  audio_source=blank()
)

let health = icecast_health()
assert(health.status == "down")
assert(list.length(health.streams) == 1)
let output_status = list.hd(health.streams)
assert(output_status.id == "icecast__test_mp3_127_0_0_1")
assert(output_status.status == "stopped")
assert(output_status.host == "127.0.0.1")
assert(output_status.port == 65534)
assert(output_status.mount == "/test.mp3")
assert(
  output_status.description ==
    "Test stream"
)
assert(not output_status.connected)

shutdown()

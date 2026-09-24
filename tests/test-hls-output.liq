# Runs the real HLS output against a temporary directory. The storage endpoint
# refuses connections, so the local writer runs while the mirror fails.
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

let STATION_ID = "test"
let HLS_BUNNY_STORAGE_ZONE = "test-zone"
let HLS_BUNNY_ACCESS_KEY = "test-key"
let HLS_BUNNY_ENDPOINT = "http://127.0.0.1:9"
let HLS_DIR = file.temp_dir(cleanup=true, "hls-test")
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 1.0
let HLS_SEGMENTS = 3
let HLS_SEGMENTS_OVERHEAD = 1

%include "../conf/lib/62_output_hls.liq"

output_hls_stream(sine())

# Tasks start after loading. An exception stops the polling task for good, so a
# separate timeout fails the test. It only prints the last recorded health, so
# nothing can block its exit.
let last_health =
  ref(
    "no health recorded"
  )
thread.run(
  delay=30.0,
  fun () ->
    begin
      print(
        "HLS output test timed out: #{last_health()}"
      )
      shutdown(code=1)
    end
)

thread.run(
  every=0.5,
  fun () ->
    begin
      let health = hls_health()
      last_health := json.stringify(health)

      # Require writer progress plus the expected failed mirror pass.
      if
        health.local.status == "ok"
        and health.local.playlist_count == 3
        and health.local.segment_count > 0
        and health.mirror.status == "degraded"
        and health.mirror.pending_segments > 0
      then
        shutdown()
      end
    end
)

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

# Poll until the real writer and mirror tick have both run. The deadline starts
# at the first poll, so script loading does not count. Errors in thread
# callbacks are only logged, so every outcome stops the process explicitly.
let deadline = ref(0.0)
thread.run(
  every=0.5,
  fun () ->
    try
      if deadline() == 0.0 then deadline := time() + 30.0 end
      let health = hls_health()

      # Local progress is only stamped by the registered on_file_change
      # handler; the mirror tick counts two variants plus the main playlist and
      # at least one segment it could not upload.
      if
        health.local.status == "ok"
        and health.local.playlist_count == 3
        and health.local.segment_count > 0
        and health.mirror.status == "degraded"
        and health.mirror.pending_segments > 0
      then
        shutdown()
      elsif
        time() > deadline()
      then
        print(
          "HLS output test timed out: #{json.stringify(health)}"
        )
        shutdown(code=1)
      end
    catch err do
      print(
        "HLS output test failed: #{error.message(err)}"
      )
      shutdown(code=1)
    end
)

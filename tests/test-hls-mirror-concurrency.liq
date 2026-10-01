# Exercise the real HLS writer against a deliberately slow local storage API.
# Variant requests must overlap; a sequential mirror cannot sustain 4s windows
# when the storage API intermittently takes seconds per mutation.
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

let STATION_ID = "test"
let HLS_BUNNY_STORAGE_ZONE = "test-zone"
let HLS_BUNNY_ACCESS_KEY = "test-key"
let HLS_BUNNY_ENDPOINT = "http://127.0.0.1:18080"
let HLS_DIR = file.temp_dir(cleanup=true, "hls-mirror-concurrency-test")
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 1.0
let HLS_SEGMENTS = 3
let HLS_SEGMENTS_OVERHEAD = 1

%include "../conf/lib/62_output_hls.liq"

let active_variant_requests = ref(0)
let max_active_variant_requests = ref(0)

harbor.http.register.regexp(
  port=18080,
  method="PUT",
  r/^\/test-zone\/test\/.*$/,
  fun (req, res) ->
    begin
      ignore(req.body())
      let is_variant =
        string.contains(substring="aac_96", req.path)
        or string.contains(substring="aac_192", req.path)

      if
        is_variant
      then
        active_variant_requests := active_variant_requests() + 1
        max_active_variant_requests :=
          max(max_active_variant_requests(), active_variant_requests())
      end

      thread.pause(0.35)

      if
        is_variant
      then
        active_variant_requests := active_variant_requests() - 1
      end

      res.status_code(201)
      res.data("")
    end
)

output_hls_stream(sine())

let last_health =
  ref(
    "no health recorded"
  )
thread.run(
  delay=25.0,
  fun () ->
    begin
      print(
        "HLS mirror concurrency test timed out: health=#{last_health()}, max \
         concurrency=#{max_active_variant_requests()}"
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

      if
        health.status == "ok"
        and health.local.playlist_count == 3
        and health.mirror.pending_segments == 0
        and health.mirror.pending_playlists == 0
        and max_active_variant_requests() >= 2
      then
        shutdown()
      end
    end
)

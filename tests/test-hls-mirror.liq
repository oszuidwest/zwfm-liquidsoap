# Deterministic publication failures: no network calls or real backoff sleeps.
let STATION_ID = "test"
let HLS_BUNNY_STORAGE_ZONE = "test-zone"
let HLS_BUNNY_ACCESS_KEY = "test-key"
let HLS_BUNNY_ENDPOINT = "https://storage.example.test/"
let HLS_DIR = file.temp_dir(cleanup=true, "hls-mirror-test")
let HLS_BITRATE_LOW = 48
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 4.0
let HLS_SEGMENTS = 10
let HLS_SEGMENTS_OVERHEAD = 5

%include "../conf/lib/62_output_hls.liq"

let playlist_name = "aac_96.m3u8"
let a = "aac_96_1000_0.ts"
let b = "aac_96_1004_1.ts"
let c = "aac_96_1008_2.ts"
let d = "aac_96_1012_3.ts"

def write_playlist(segments) =
  let content = "#EXTM3U\n" ^ string.concat(separator="\n", segments) ^ "\n"
  file.write(data=content, "#{HLS_DIR}/#{playlist_name}")
  content
end

let fake_now = ref(1004.0)
let calls = ref([])
let messages = ref([])
let fail_files = ref(false)
let fail_playlist = ref(false)
let raise_exception = ref(false)
let upload_hook = ref(fun () -> ())

def report(_, message) =
  messages := [...messages(), message]
end

def has_message(part) =
  list.exists(
    fun (message) -> string.contains(substring=part, message),
    messages()
  )
end

def fake_put(name, fail, reason, on_error) =
  calls := [...calls(), name]
  let hook = upload_hook()
  hook()
  if fail then on_error("upload_failed", reason) end
  not fail
end

def put_file(local_path, ~on_error) =
  if
    raise_exception()
  then
    error.raise(
      error.invalid,
      "transport exception"
    )
  end
  fake_put(
    path.basename(local_path),
    fail_files(),
    "simulated HTTP 522 timeout",
    on_error
  )
end

def put_data(remote_name, _, ~on_error) =
  fake_put(
    remote_name,
    fail_playlist(),
    "simulated HTTP 523 DNS failure",
    on_error
  )
end

def create_worker() =
  hls_create_playlist_worker(
    playlist_name,
    now=fake_now,
    put_file=put_file,
    put_data=put_data,
    report=report
  )
end

assert(hls_publication_timeout == 4.0)
assert(hls_publication_retry_delay_max == 4.0)
assert(hls_newest_segment_time([]) == null)
assert(hls_newest_segment_time(["legacy.ts"]) == null)
assert(hls_newest_segment_time([a, b]) == 1004.0)

# Keep the production filename format and timestamp units in sync with health.
let before_name = float_of_int(int_of_float(time()))
let generated_time =
  hls_newest_segment_time(
    [hls_segment_name({stream_name = "aac_96", position = 7, extname = "ts"})]
  )
assert(null.defined(generated_time))
assert(null.get(generated_time) >= before_name)
assert(null.get(generated_time) <= time())

# Segment retries back off 1, 2, 4, 4 seconds. No playlist can be uploaded
# before all required segments have acknowledged uploads.
let first = write_playlist([a, b])
let worker = create_worker()
fail_files := true
worker.run()
assert(calls() == [a])
assert(worker.pending() == {segments = 2, playlists = 1})
assert(worker.published_at() == null)
worker.run()
assert(calls() == [a])
fake_now := 1005.0
worker.run()
fake_now := 1006.0
worker.run()
assert(list.length(calls()) == 2)
fake_now := 1007.0
worker.run()
fake_now := 1010.0
worker.run()
assert(list.length(calls()) == 3)
fake_now := 1011.0
worker.run()
assert(list.length(calls()) == 4)
assert(has_message("attempt=4"))
assert(worker.error() == "upload_failed")
fail_files := false
fake_now := 1015.0
worker.run()
assert(calls() == [a, a, a, a, a, b, playlist_name])
assert(worker.synced_playlist() == first)
assert(worker.error() == "")
assert(worker.pending() == {segments = 0, playlists = 0})
assert(worker.published_at() == 1004.0)
assert(worker.recovered_uploads() == 1)
assert(
  has_message(
    "#{a} after 4 failed attempt(s)"
  )
)

# No-op passes must not make the published audio look newer.
fake_now := 1020.0
worker.run()
assert(worker.published_at() == 1004.0)
assert(list.length(calls()) == 7)

# A failed playlist PUT preserves the old publication and retries the playlist
# without re-uploading already acknowledged segments.
ignore(write_playlist([b, c]))
fail_playlist := true
calls := []
worker.run()
assert(calls() == [c, playlist_name])
assert(worker.synced_playlist() == first)
assert(worker.pending() == {segments = 0, playlists = 1})
fail_playlist := false
fake_now := 1021.0

# Simulate the writer advancing during a slow playlist PUT. Pending must see
# the new window, not last pass's zero backlog.
upload_hook :=
  fun () ->
    begin
      ignore(write_playlist([c, d]))
      assert(worker.pending() == {segments = 1, playlists = 1})
    end
worker.run()
upload_hook := fun () -> ()
assert(calls() == [c, playlist_name, playlist_name])
assert(worker.pending() == {segments = 1, playlists = 1})
assert(worker.published_at() == 1008.0)
assert(worker.recovered_uploads() == 2)
worker.run()
assert(worker.pending() == {segments = 0, playlists = 0})
assert(worker.published_at() == 1012.0)

# A prolonged outage retains the last acknowledged playlist. Once the writer
# has moved on, expired unconfirmed segments (even unattempted ones) are
# explicitly counted, but never claimed to have failed delivery at storage.
fake_now := 2000.0
let previous = write_playlist([a])
let outage = create_worker()
outage.run()
ignore(write_playlist([b, c]))
fail_files := true
calls := []
outage.run()
for _ = 1 to 20 do
  fake_now := fake_now() + 4.0
  outage.run()

end
assert(list.length(calls()) == 21)
assert(outage.synced_playlist() == previous)
assert(outage.desired_segments() == [b, c])
assert(outage.published_at() == 1000.0)
assert(outage.expired_segments() == 0)
ignore(write_playlist([d]))
assert(outage.pending() == {segments = 1, playlists = 1})
fail_files := false
fake_now := fake_now() + 4.0
calls := []
outage.run()
assert(calls() == [d, playlist_name])
assert(outage.expired_segments() == 2)
assert(outage.recovered_uploads() == 0)
list.iter(
  fun (message) -> assert(has_message(message)),
  [
    "segment expired for #{b} after 21 failed attempt(s)",
    "segment expired for #{c} after 0 failed attempt(s)",
    "remote delivery unknown"
  ]
)
outage.run()
assert(outage.expired_segments() == 2)

# Transport exceptions are contained and remain retryable.
ignore(write_playlist([a]))
let exception_worker = create_worker()
raise_exception := true
exception_worker.run()
assert(exception_worker.error() == "worker_failed")
assert(exception_worker.published_at() == null)
raise_exception := false
fake_now := fake_now() + 1.0
exception_worker.run()
assert(exception_worker.error() == "")
assert(exception_worker.published_at() == 1000.0)

# Waiting for the writer leaves publication unknown and makes no requests.
let ready = ref(false)
let waiting =
  hls_create_playlist_worker(
    playlist_name,
    ready=ready,
    now=fake_now,
    put_file=put_file,
    put_data=put_data,
    report=report
  )
calls := []
waiting.run()
assert(waiting.error() == "")
assert(waiting.published_at() == null)
assert(waiting.pending().playlists == 1)
assert(calls() == [])
ready := true
waiting.run()
assert(waiting.published_at() == 1000.0)
assert(calls() == [a, playlist_name])

# Health totals include recovery/expiry across workers, excluding the static
# master's null timestamp from published audio freshness.
let master = hls_create_playlist_worker(hls_main_playlist_name)
hls_mirror_health_tick(master, [worker, outage], {error = fun () -> ""})
assert(hls_health().mirror.recovered_uploads == 2)
assert(hls_health().mirror.expired_segments == 2)
assert(hls_mirror_last_published_at() == 1012.0)

# The retry ceiling also bounds the first retry for sub-second segments.
let short_calls = ref(0)
let short =
  hls_create_mirror_worker(
    "short interval",
    retry_delay_max=0.5,
    now=fake_now,
    report=report,
    fun (on_error) ->
      begin
        short_calls := short_calls() + 1
        on_error(
          "upload_failed",
          "simulated timeout"
        )
      end
  )
short.run()
fake_now := fake_now() + 0.5
short.run()
assert(short_calls() == 2)

shutdown()

# HLS health and filesystem failure tests.
let STATION_ID = "test"
let HLS_BUNNY_STORAGE_ZONE = "test-zone"
let HLS_BUNNY_ACCESS_KEY = "test-key"
let HLS_BUNNY_ENDPOINT = "https://storage.example.test/"
let HLS_DIR = file.temp_dir(cleanup=true, "hls-status-test")
let HLS_BITRATE_LOW = 48
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 4.0
let HLS_SEGMENTS = 10
let HLS_SEGMENTS_OVERHEAD = 5

%include "../conf/lib/62_output_hls.liq"

def mirror_worker(error_code, segments, playlists, published_at) =
  {
    error = ref(error_code),
    pending = fun () -> {segments = segments, playlists = playlists},
    published_at = ref(published_at),
    recovered_uploads = ref(0),
    expired_segments = ref(0)
  }
end

let starting = hls_health()
assert(starting.status == "starting")
assert(starting.local.status == "starting")
assert(starting.mirror.status == "starting")
assert(starting.mirror.host == "storage.example.test")
assert(starting.mirror.storage_zone == "test-zone")
assert(not null.defined(starting.local.update_age_seconds))
assert(not null.defined(starting.mirror.published_age_seconds))

# Startup stalls after the grace period.
hls_started_at := time() - hls_stale_after_seconds - 1.0
let never_started = hls_health()
assert(never_started.local.status == "degraded")
assert(never_started.mirror.status == "degraded")
hls_started_at := time()

file.write(data="#EXTM3U", "#{HLS_DIR}/aac_96.m3u8")
file.write(data="#EXTM3U", "#{HLS_DIR}/live.m3u8")
file.write(data="", "#{HLS_DIR}/aac_96_1.ts")
file.write(data="", "#{HLS_DIR}/aac_96_2.ts")
hls_local_file_names :=
  ["aac_96.m3u8", "live.m3u8", "aac_96_1.ts", "aac_96_2.ts"]
hls_local_last_update_at := time()

let now = time()
let cleanup_error = ref("listing_failed")
let cleanup_worker = {error = cleanup_error}
let oldest_worker = mirror_worker("upload_failed", 1, 0, now - 5.0)
let newest_worker = mirror_worker("", 2, 1, now)
hls_mirror_health_tick(newest_worker, [oldest_worker], cleanup_worker)
assert(hls_mirror_error() == "listing_failed")
assert(hls_mirror_pending() == {segments = 3, playlists = 1})
assert(hls_mirror_last_published_at() == oldest_worker.published_at())

cleanup_error := ""
hls_mirror_health_tick(
  oldest_worker,
  [mirror_worker("", 0, 0, null)],
  cleanup_worker
)
assert(hls_mirror_error() == "upload_failed")
assert(not null.defined(hls_mirror_last_published_at()))

hls_mirror_health_tick(
  mirror_worker("", 1, 0, time()),
  [mirror_worker("", 0, 0, time())],
  cleanup_worker
)

let healthy = hls_health()
assert(healthy.status == "ok")
assert(healthy.local.status == "ok")
assert(healthy.local.playlist_count == 2)
assert(healthy.local.segment_count == 2)
assert(null.get(healthy.local.update_age_seconds) < 1.0)
assert(not null.defined(healthy.local.error))
assert(healthy.mirror.status == "ok")
assert(null.get(healthy.mirror.published_age_seconds) < 1.0)
assert(healthy.mirror.recovered_uploads == 0)
assert(healthy.mirror.expired_segments == 0)
assert(healthy.mirror.pending_segments == 1)
assert(healthy.mirror.pending_playlists == 0)
assert(not null.defined(healthy.mirror.error))

# Preserve null errors when spreading health records.
let encoded = json.stringify(compact=true, healthy)
assert(string.contains(substring="\"error\":null", encoded))
assert(string.contains(substring="\"pending_segments\":1", encoded))
assert(not string.contains(substring="\"sync_age_seconds\":", encoded))
assert(string.contains(substring="\"published_age_seconds\":", encoded))

# Freshness follows the stalest variant and excludes the static master playlist.
hls_mirror_health_tick(
  mirror_worker("", 0, 0, time()),
  [
    mirror_worker("", 0, 0, time() - hls_stale_after_seconds - 1.0),
    mirror_worker("", 0, 0, time())
  ],
  cleanup_worker
)
assert(hls_health().mirror.status == "degraded")
assert(hls_health().mirror.error == "stalled")
hls_mirror_health_tick(
  mirror_worker("", 0, 0, null),
  [mirror_worker("", 0, 0, time())],
  cleanup_worker
)
assert(hls_health().mirror.status == "ok")

# Only created or updated playlists count as writer progress.
hls_local_last_update_at := null
hls_local_file_names := []
hls_track_local_progress({path = "/hls/aac_96_1.ts", state = "created"})
hls_track_local_progress({path = "/hls/aac_96.m3u8", state = "deleted"})
assert(not null.defined(hls_local_last_update_at()))
hls_track_local_progress({path = "/hls/aac_96.m3u8", state = "updated"})
assert(null.defined(hls_local_last_update_at()))
assert(hls_health().local.playlist_count == 1)

hls_local_last_update_at := time() - hls_stale_after_seconds - 1.0
let stale = hls_health()
assert(stale.status == "degraded")
assert(stale.local.status == "degraded")
assert(null.get(stale.local.error) == "stalled")

# Unreadable HLS_DIR must not break cleanup or health checks. Requires non-root.
hls_local_last_update_at := time()
ignore(
  process.run(
    "chmod 000 #{HLS_DIR}"
  )
)
let listing_caught = ref(false)
try
  ignore(file.ls(HLS_DIR))
catch _ do
  listing_caught := true
end
assert(listing_caught())
hls_remove_stale_local_files()
let unreadable = hls_health()
assert(unreadable.local.status == "ok")
assert(not null.defined(unreadable.local.error))
assert(unreadable.local.playlist_count == 0)
ignore(
  process.run(
    "chmod 700 #{HLS_DIR}"
  )
)

# A missing HLS_DIR degrades local health even with fresh writer progress.
hls_local_last_update_at := time()
file.rmdir(HLS_DIR)
let missing = hls_health()
assert(missing.status == "degraded")
assert(missing.local.status == "degraded")
assert(null.get(missing.local.error) == "dir_missing")
assert(missing.local.playlist_count == 0)

let upload_error = ref("")
assert(
  not hls_put_file(
    on_error=fun (code, _) -> upload_error := code,
    "#{HLS_DIR}/missing.ts"
  )
)
assert(upload_error() == "local_file_missing")

shutdown()

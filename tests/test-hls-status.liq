# Minimal settings required to load and exercise the HLS status helpers.
let STATION_ID = "test"
let HLS_BUNNY_STORAGE_ZONE = "test-zone"
let HLS_BUNNY_ACCESS_KEY = "test-key"
let HLS_BUNNY_ENDPOINT = "https://storage.example.test/"
let HLS_DIR = "/hls"
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 4.0
let HLS_SEGMENTS = 10
let HLS_SEGMENTS_OVERHEAD = 5

%include "../conf/lib/62_output_hls.liq"

let starting = hls_health()
assert(starting.status == "starting")
assert(starting.local.status == "starting")
assert(starting.mirror.status == "starting")
assert(starting.mirror.host == "storage.example.test")
assert(starting.mirror.storage_zone == "test-zone")
assert(not null.defined(starting.local.last_update_at))
assert(not null.defined(starting.mirror.last_sync_at))

let playlists =
  [
    {name = "aac_96.m3u8", content = "#EXTM3U\naac_96_1.ts"},
    {name = "live.m3u8", content = "#EXTM3U\naac_96.m3u8"}
  ]
let segment_files = ["/hls/aac_96_1.ts", "/hls/aac_96_2.ts"]
let synced_segments = ref(["aac_96_1.ts"])
let synced_playlists =
  ref(
    [
      ("aac_96.m3u8", "#EXTM3U\naac_96_1.ts"),
      ("live.m3u8", "#EXTM3U\naac_96.m3u8")
    ]
  )

hls_update_local_progress(playlists, segment_files)
hls_update_mirror_progress(
  playlists,
  ["aac_96_1.ts", "aac_96_2.ts"],
  synced_segments,
  synced_playlists,
  true
)

let healthy = hls_health()
assert(healthy.status == "ok")
assert(healthy.local.status == "ok")
assert(healthy.local.playlist_count == 2)
assert(healthy.local.segment_count == 2)
assert(null.defined(healthy.local.last_update_at))
assert(null.get(healthy.local.update_age_seconds) < 1.0)
assert(not null.defined(healthy.local.error))
assert(healthy.mirror.status == "ok")
assert(null.defined(healthy.mirror.last_sync_at))
assert(null.get(healthy.mirror.sync_age_seconds) < 1.0)
assert(healthy.mirror.synced_segments == 1)
assert(healthy.mirror.pending_segments == 1)
assert(healthy.mirror.synced_playlists == 2)
assert(healthy.mirror.pending_playlists == 0)
assert(not null.defined(healthy.mirror.error))

let encoded = json.stringify(compact=true, healthy)
assert(not string.contains(substring="\"detail\"", encoded))
assert(string.contains(substring="\"host\":\"storage.example.test\"", encoded))
assert(string.contains(substring="\"storage_zone\":\"test-zone\"", encoded))

hls_local_last_update_at := time() - hls_stale_after_seconds - 1.0
let stale = hls_health()
assert(stale.status == "degraded")
assert(stale.local.status == "degraded")
assert(null.defined(stale.local.error))

shutdown()

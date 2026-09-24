# Load the HLS health helpers with minimal configuration.
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
assert(not null.defined(starting.local.update_age_seconds))
assert(not null.defined(starting.mirror.sync_age_seconds))

let playlists =
  [
    {name = "aac_96.m3u8", content = "#EXTM3U\naac_96_1.ts"},
    {name = "live.m3u8", content = "#EXTM3U\naac_96.m3u8"}
  ]
let synced_playlists =
  [
    ("aac_96.m3u8", "#EXTM3U\naac_96_1.ts"),
    ("live.m3u8", "#EXTM3U\naac_96.m3u8")
  ]

# Simulate a complete, successful mirror pass.
hls_local_last_update_at := time()
hls_mirror_state :=
  {
    playlists = playlists,
    segment_names = ["aac_96_1.ts", "aac_96_2.ts"],
    synced_segments = ["aac_96_1.ts"],
    synced_playlists = synced_playlists
  }
hls_mirror_last_sync_at := time()

let healthy = hls_health()
assert(healthy.status == "ok")
assert(healthy.local.status == "ok")
assert(healthy.local.playlist_count == 2)
assert(healthy.local.segment_count == 2)
assert(null.get(healthy.local.update_age_seconds) < 1.0)
assert(not null.defined(healthy.local.error))
assert(healthy.mirror.status == "ok")
assert(null.get(healthy.mirror.sync_age_seconds) < 1.0)
assert(healthy.mirror.pending_segments == 1)
assert(healthy.mirror.pending_playlists == 0)
assert(not null.defined(healthy.mirror.error))

# Guard record-spread serialization.
let encoded = json.stringify(compact=true, healthy)
assert(string.contains(substring="\"error\":null", encoded))
assert(string.contains(substring="\"pending_segments\":1", encoded))

# Only created or updated playlists count as writer progress.
hls_local_last_update_at := null
hls_track_local_progress({path = "/hls/aac_96_1.ts", state = "created"})
hls_track_local_progress({path = "/hls/aac_96.m3u8", state = "deleted"})
assert(not null.defined(hls_local_last_update_at()))
hls_track_local_progress({path = "/hls/aac_96.m3u8", state = "updated"})
assert(null.defined(hls_local_last_update_at()))

hls_local_last_update_at := time() - hls_stale_after_seconds - 1.0
let stale = hls_health()
assert(stale.status == "degraded")
assert(stale.local.status == "degraded")
assert(null.defined(stale.local.error))

shutdown()

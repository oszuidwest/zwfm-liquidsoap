# HLS operations

Liquidsoap writes an audio-only HLS live window to `HLS_DIR` and mirrors it to Bunny Storage, where a Bunny CDN pull zone serves the files to players. HLS is enabled when `HLS_BUNNY_STORAGE_ZONE` and `HLS_BUNNY_ACCESS_KEY` are set. The mirror writes to `https://<HLS_BUNNY_ENDPOINT>/<HLS_BUNNY_STORAGE_ZONE>/<STATION_ID>/`.

## Local writer

Compose mounts a 64 MB tmpfs at `/hls` in the container, so keep `HLS_DIR=/hls` with the provided Compose file. The live segments disappear when the container stops, and a full or read-only host filesystem cannot stop the writer.

The default ladder has three MPEG-TS variants: `aac_48.m3u8` with HE-AAC (`mp4a.40.5`) at 48 kbps (`HLS_BITRATE_LOW`), `aac_96.m3u8` with AAC-LC (`mp4a.40.2`) at 96 kbps (`HLS_BITRATE_MID`), and `aac_192.m3u8` with AAC-LC at 192 kbps (`HLS_BITRATE_HIGH`). The bitrate variables change the encoded bitrates but not the playlist names. Each segment carries the stream metadata as timed ID3, and a ladder with both HE-AAC and AAC-LC needs Liquidsoap 2.4.6 or later.

`live.m3u8` is the main playlist. The defaults are 4-second segments (`HLS_SEGMENT_DURATION`) and 10 segments per media playlist (`HLS_SEGMENTS`). `HLS_SEGMENTS_OVERHEAD` defaults to `HLS_SEGMENTS + 3` (13). Liquidsoap deletes the oldest local segment when a variant has 23 segments on disk, so 12 segments that left the playlist stay available for clients that lag behind. Segment names are `<stream>_<unix time>_<position>.ts`. The names are unique across restarts, so the CDN can cache segments for a long time and the writer needs no persisted state. On every (re)start, the writer removes old playlists, segments, and temporary files from `HLS_DIR`.

## Mirror

Each variant playlist has its own mirror worker, and the main playlist has a fourth. Every worker runs once per second. On each pass it reads the newest local playlist, counts the segments that left the playlist without a confirmed upload as expired, uploads every unconfirmed segment in playlist order and stops at the first failure, and uploads the playlist when all its segments are confirmed and the content changed. A playlist is therefore published only after all segments in it are on the remote side, and when an upload fails, the previous valid playlist stays online. The main playlist is uploaded only after every variant playlist has been published at least once. Older local segments that are no longer in the playlist are skipped.

Uploads use `http.put` with a timeout of `max(0.1, min(10.0, HLS_SEGMENT_DURATION))` seconds, 4 seconds with the defaults. After a failed pass, the worker waits before the next pass. The delay starts at 1 second, doubles up to `max(0.1, min(4.0, HLS_SEGMENT_DURATION))` seconds (also 4 seconds with the defaults), and resets after a successful pass. Every failed upload is logged with its attempt number, a success after earlier failures is logged as recovered and counted in `recovered_uploads`, and a segment that leaves the playlist without a confirmed upload is logged as expired and counted in `expired_segments`.

## Remote cleanup

A cleanup worker runs every 30 seconds, after every variant has been published at least once. It lists the remote directory and deletes every segment that is not protected. A segment is protected when it is still on local disk, in a current local playlist, or in a published playlist. A `404` on delete counts as success. The listing happens before the deletes, so a segment that is being uploaded cannot become a deletion candidate, and when the listing fails, nothing is deleted. The cleanup worker retries with a delay that doubles from 1 second to 30 seconds, and its requests time out after 10 seconds. Because 12 removed segments stay on local disk, a segment stays online for at least one segment duration plus one playlist duration after it leaves the playlist. This satisfies [RFC 8216 section 6.2.2](https://www.rfc-editor.org/rfc/rfc8216#section-6.2.2).

## Failure isolation and health

- The HLS source runs on its own clock. A clock error sets `local.error` to `clock_error` and does not affect the other outputs. Before the writer starts, it checks that `HLS_DIR` is writable, otherwise `local.error` is `dir_not_writable`.
- A watchdog runs every 5 seconds and recreates the writer when it is degraded. The delay between attempts doubles from 5 seconds to 5 minutes and resets after 2 minutes without problems. The writer does not use `persist_at`, because writing state during a clock error can stop the whole process.
- Mirror and cleanup workers catch their own exceptions and report them as `worker_failed`. They do not stop the writer or the other outputs. Health values are sampled every second by a separate task, so a blocked upload does not freeze the status.

The local writer becomes `degraded` with error `stalled` when no playlist is written for `max(15.0, HLS_SEGMENT_DURATION * 4.0)` seconds, which is 16 seconds with the defaults. The mirror uses the same threshold for `published_age_seconds`, so uploads can succeed and the mirror can still report `stalled` when the published audio is too old. A slow but successful upload can exceed the threshold, and upload timeouts do not extend it. When the local writer stalls, the mirror stalls with it, so if both report `stalled`, check the writer first. The fields and error codes are described in [Status API](status-api.md#outputshls).

## Bunny setup

1. Create a Bunny Storage zone for HLS only, so that its password gives access to the live stream objects only. Note its read/write password and its regional API endpoint.
2. Set `HLS_BUNNY_STORAGE_ZONE`, `HLS_BUNNY_ACCESS_KEY`, and `HLS_BUNNY_ENDPOINT`, then connect the storage zone to a Bunny CDN pull zone and configure its hostname.
3. Enable CORS for the `m3u8` and `ts` extensions if browsers play the stream from another origin.
4. Set a cache time of 1 to 2 seconds for `*.m3u8` and a long cache time, for example one day, for `.ts` files. Keep Perma-Cache disabled, because live playlists are overwritten in place.

The player URL is `https://hls.example.com/{STATION_ID}/live.m3u8`. Check the public stream with `ffprobe https://hls.example.com/zuidwest/live.m3u8` and the cache headers with `curl --silent --head https://hls.example.com/zuidwest/live.m3u8`. Expect one `mp4a.40.5` variant and two `mp4a.40.2` variants, media playlists that change, no segment that returns `404`, and cache lifetimes that match the configuration. HLS clients must pass timed ID3 metadata to the player application; in hls.js, use the `Hls.Events.FRAG_PARSING_METADATA` event.

## Troubleshooting

Check `hls.status`. `local=<code>` shows a writer or tmpfs problem, and `mirror=<code>` shows an upload problem or old published audio. If both show `stalled`, check the writer first. If only the mirror is stalled, check the upload latency and the pending counts in `GET /status`, the Bunny credentials and endpoint, and the playlist cache rule and CORS settings of the pull zone. Check the tmpfs with `docker exec liquidsoap df -h /hls`.

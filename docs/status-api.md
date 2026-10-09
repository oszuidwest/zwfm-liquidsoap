# Status API

`GET /status` returns the runtime state of the container as JSON. The endpoint is registered only when `STATUS_BEARER_TOKEN` is set. Use a different token than for `POST /metadata`.

```bash
curl --fail-with-body --silent --header "Authorization: Bearer ${STATUS_BEARER_TOKEN}" http://127.0.0.1:7000/status | jq
```

The response code is `200` for `ok` and `degraded`, `503` for `down`, and `401` for a missing or invalid token. Responses carry `Cache-Control: no-store`. The JSON schema is stable: unavailable scalar values are `null`, collections are always arrays, and error fields contain error codes, never log text.

## Top-level fields

| Field                        | Meaning                                                                                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `status`                     | `ok`, `degraded`, or `down`                                                                                                                  |
| `station_id`, `timestamp`, `silence_detection_enabled` | `STATION_ID`, the Unix time of the snapshot, and the silence detection state                                                    |
| `radio`                      | `ready` (the radio source can produce audio), `mode` (`auto` or `forced`), and `active_source` (`studio_a`, `studio_b`, `fallback`, or `unknown`) |
| `sources[]`                  | `name` and `ready` for each source in the fallback chain                                                                                     |
| `studio_inputs[]`, `outputs` | See below; `outputs` has `icecast`, `dab`, and `hls`                                                                                         |

`status` is `down` when the radio source is not ready, and `degraded` when the emergency source is active or an enabled output is not healthy. An output is healthy when its status is `ok`, `starting`, `unmonitored`, or `disabled`.

## studio_inputs

| Field                                | Meaning                                                                                         |
| ------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `name`                               | `studio_a` or `studio_b`                                                                        |
| `status`                             | `down` (no caller connected), `degraded` (silent, reported only while silence detection is enabled), `starting` (buffer filling), or `ok` |
| `error`                              | `disconnected`, `silent`, or `null`                                                             |
| `buffer_seconds`                     | Buffered audio in seconds                                                                       |
| `audio.rms_dbfs`, `audio.peak_dbfs`  | `left` and `right` levels over the last 0.5 seconds in dBFS, clamped at -120 and `null` while disconnected |
| `srt`                                | `connected` (`true` when at least one SRT caller is connected) and `connections[]` with `peer`, `latency_ms`, `receive_buffer_ms`, `rtt_ms`, `dropped_packets_total`, and `statistics_error` (`statistics_unavailable` when the SRT statistics failed; the metrics are then `null`) per caller |

## outputs.icecast

`status` is `ok` when every Icecast output is connected, `degraded` when some are, `down` when none are, and `disabled` when there are no Icecast outputs. `streams[]` lists every output, including the DME outputs, with `id` (derived from the mount and host), `host`, `port`, `mount`, and `connected`.

## outputs.dab

| Status        | Meaning                                                                  |
| ------------- | ------------------------------------------------------------------------ |
| `disabled`    | DAB+ is not configured                                                   |
| `unmonitored` | Monitoring is disabled, or no TCP destination is configured              |
| `starting`    | All TCP destinations are in their startup grace period                   |
| `ok`          | Every TCP destination has recent ACK progress                            |
| `degraded`    | Destinations have mixed health, or an ACK warning threshold was exceeded |
| `down`        | Every TCP destination is down, or ODR-AudioEnc crashed recently          |

`error` is `encoder_error` for 30 seconds after an ODR-AudioEnc crash, `monitor_failed` when the ACK monitor gave no usable result, and `null` otherwise. `destinations[]` has one record per EDI destination: `destination` (the URL), `status` (`unmonitored`, `starting`, `ok`, `degraded`, or `down`), `tcp_state` (as reported by `ss`, for example `ESTAB`), `ack_age_seconds` (seconds since the last ACK progress), the TCP counters `bytes_sent`, `bytes_acked`, `send_queue_bytes`, `unacked_segments`, and `retransmissions`, and `error`. The error is `ack_stalled` when there is no ACK progress within the warning or down threshold, `no_socket` when ODR-AudioEnc has no TCP socket to the destination, `tcp_not_established` when the socket is not in the `ESTAB` state, `invalid_destination` when the URL has no valid host or port, and `monitor_failed` when the monitor returned no result for it.

The monitor is the shell script `bin/dab-tcp-ack-monitor`. Liquidsoap runs it every `DAB_ACK_POLL_SECONDS` (minimum 0.25 seconds), and the script reads the Linux TCP metrics of the ODR-AudioEnc socket for each `tcp://` destination with `ss`. UDP destinations are reported as `unmonitored`. A destination makes ACK progress when `bytes_acked` grows between two polls. It is `starting` while it has no progress yet and the connection is younger than `DAB_ACK_STARTUP_GRACE_SECONDS`, `ok` when the last progress is at most `DAB_ACK_WARN_SECONDS` ago, `degraded` when it is at most `DAB_ACK_DOWN_SECONDS` ago, and `down` after that. The script keeps its state per destination in `/dev/shm/dab-ack-monitor/state`. A TCP ACK proves only that the remote TCP stack received the data, so it says nothing about whether ODR-DabMux processed it.

The `dab.status` server command shows the same state as text. The first line is the overall status, followed by `: <code>` when there is an aggregate error. Each destination line shows the destination, its status, its error code if there is one, and the TCP counters when the socket is connected, for example `tcp://primary.example.com:9001 ok ack_age=0s bytes_sent=123456 bytes_acked=123457 send_queue=0 unacked=0 retrans=0`.

## outputs.hls

| Field                                                | Meaning                                                                                                                                                                                                   |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `status`                                             | `disabled`, `starting`, `ok`, or `degraded`                                                                                                                                                               |
| `local.status`, `local.error`                        | Health of the local writer; the error is `dir_missing`, `dir_not_writable`, `clock_error`, `stalled`, or `null`                                                                                           |
| `local.playlist_count`, `local.segment_count`, `local.update_age_seconds` | Playlists and segments in `HLS_DIR`, and seconds since a local playlist was last written                                                                                             |
| `mirror.status`, `mirror.error`                      | Health of the Bunny mirror; the error is `listing_failed`, `upload_failed`, `delete_failed`, `read_failed`, `local_file_missing`, `worker_failed`, `stalled`, or `null`                                   |
| `mirror.host`, `mirror.storage_zone`                 | Bunny Storage endpoint host and `HLS_BUNNY_STORAGE_ZONE`                                                                                                                                                  |
| `mirror.published_age_seconds`                       | Age of the newest confirmed segment of the variant that is furthest behind, measured from the generation time in the segment name; `null` until every variant has a published playlist with a known segment time |
| `mirror.pending_segments`, `mirror.pending_playlists` | Segments and playlists in the current local playlists that are not confirmed remotely, counted every second and including running uploads; the main playlist counts as one pending playlist until it is published |
| `mirror.recovered_uploads`                           | Uploads that succeeded after one or more failed attempts for the same object name; resets when the process restarts                                                                                       |
| `mirror.expired_segments`                            | Segments that left a live playlist without a confirmed upload, including segments never tried because an earlier one failed; such a segment may still exist remotely; resets when the process restarts    |

`status` is `degraded` when the writer or the mirror is degraded, `starting` when one of them has not made progress yet, and `ok` otherwise. The writer and the mirror both report `stalled` after `max(15.0, HLS_SEGMENT_DURATION * 4.0)` seconds without progress, which is 16 seconds with the defaults; [HLS operations](hls-operations.md#failure-isolation-and-health) explains the threshold. The `hls.status` server command shows the overall status followed by `: local=<code>` and `mirror=<code>` when there are errors.

## Error code summary

| Field                                                | Codes                                                                                                                 |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `studio_inputs[].error`                              | `disconnected`, `silent`                                                                                              |
| `studio_inputs[].srt.connections[].statistics_error` | `statistics_unavailable`                                                                                              |
| `outputs.dab.error`                                  | `encoder_error`, `monitor_failed`                                                                                     |
| `outputs.dab.destinations[].error`                   | `ack_stalled`, `no_socket`, `tcp_not_established`, `invalid_destination`, `monitor_failed`                            |
| `outputs.hls.local.error`                            | `dir_missing`, `dir_not_writable`, `clock_error`, `stalled`                                                           |
| `outputs.hls.mirror.error`                           | `listing_failed`, `upload_failed`, `delete_failed`, `read_failed`, `local_file_missing`, `worker_failed`, `stalled`   |

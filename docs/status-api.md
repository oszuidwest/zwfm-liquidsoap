# Status API

`GET /status` returns the runtime state of the container as JSON. The endpoint is registered only when `STATUS_BEARER_TOKEN` is set. Use a different token than for `POST /metadata`.

```bash
curl --fail-with-body --silent \
  --header "Authorization: Bearer ${STATUS_BEARER_TOKEN}" \
  http://127.0.0.1:7000/status | jq
```

The HTTP response code is `200` for `ok` and `degraded`, `503` for `down`, and `401` for a missing or invalid token. Responses are sent with `Cache-Control: no-store`.

The JSON schema is stable. Unavailable scalar values are `null`. Collections are always arrays. Error fields contain error codes, never log text.

## Top-level fields

| Field                       | Meaning                                                              |
| --------------------------- | -------------------------------------------------------------------- |
| `status`                    | `ok`, `degraded`, or `down`                                          |
| `station_id`                | `STATION_ID`                                                         |
| `timestamp`                 | Unix time of the snapshot                                            |
| `radio.ready`               | `true` when the radio source can produce audio                       |
| `radio.mode`                | `auto` or `forced`                                                   |
| `radio.active_source`       | `studio_a`, `studio_b`, `fallback`, or `unknown`                     |
| `silence_detection_enabled` | Current silence detection state                                      |
| `sources[]`                 | `name` and `ready` for each source in the fallback chain             |
| `studio_inputs[]`           | One record per studio input, see below                               |
| `outputs`                   | `icecast`, `dab`, and `hls`, see below                               |

`status` is `down` when the radio source is not ready. It is `degraded` when the emergency source is active, or when an enabled output is not healthy. An output is healthy when its status is `ok`, `starting`, `unmonitored`, or `disabled`.

## studio_inputs

| Field                                  | Meaning                                                   |
| -------------------------------------- | --------------------------------------------------------- |
| `name`                                 | `studio_a` or `studio_b`                                  |
| `status`                               | `down`, `degraded`, `starting`, or `ok`                   |
| `error`                                | `disconnected`, `silent`, or `null`                       |
| `buffer_seconds`                       | Buffered audio in seconds                                 |
| `audio.rms_dbfs.left` / `.right`       | RMS level over the last 0.5 seconds, in dBFS              |
| `audio.peak_dbfs.left` / `.right`      | Peak level over the last 0.5 seconds, in dBFS             |
| `srt.connected`                        | `true` when at least one SRT caller is connected          |
| `srt.connections[].peer`               | Caller address                                            |
| `srt.connections[].latency_ms`         | SRT receive delay                                         |
| `srt.connections[].receive_buffer_ms`  | SRT receive buffer                                        |
| `srt.connections[].rtt_ms`             | Round-trip time                                           |
| `srt.connections[].dropped_packets_total` | Dropped packets since the connection started           |
| `srt.connections[].statistics_error`   | `statistics_unavailable` when the SRT statistics failed   |

The status is `down` when no caller is connected, `degraded` when the input is silent, `starting` while the buffer fills, and `ok` when the input is ready. Silence is only reported while silence detection is enabled. Levels are clamped at -120 dBFS and are `null` when the input is disconnected. When the SRT statistics cannot be read, the connection is still listed and only its metrics are `null`.

## outputs.icecast

| Field               | Meaning                                              |
| ------------------- | ---------------------------------------------------- |
| `status`            | `disabled`, `ok`, `degraded`, or `down`              |
| `streams[].id`      | Stable ID derived from the mount and host            |
| `streams[].host`    | Icecast host                                         |
| `streams[].port`    | Icecast port                                         |
| `streams[].mount`   | Mount point                                          |
| `streams[].connected` | `true` while the output is connected               |

The status is `ok` when every output is connected, `degraded` when some are connected, `down` when none are connected, and `disabled` when there are no Icecast outputs. The DME outputs are included in this list.

## outputs.dab

| Status        | Meaning                                                                   |
| ------------- | ------------------------------------------------------------------------- |
| `disabled`    | DAB+ is not configured                                                    |
| `unmonitored` | Monitoring is disabled, or no TCP destination is configured               |
| `starting`    | All TCP destinations are in their startup grace period                    |
| `ok`          | Every TCP destination has recent ACK progress                             |
| `degraded`    | Destinations have mixed health, or an ACK warning threshold was exceeded  |
| `down`        | Every TCP destination is down, or ODR-AudioEnc crashed recently           |

`error` is `encoder_error` for 30 seconds after an ODR-AudioEnc crash, `monitor_failed` when the ACK monitor gave no usable result, and `null` otherwise.

| Field                              | Meaning                                                  |
| ---------------------------------- | -------------------------------------------------------- |
| `destinations[].destination`       | EDI destination URL                                      |
| `destinations[].status`            | `unmonitored`, `starting`, `ok`, `degraded`, or `down`   |
| `destinations[].tcp_state`         | TCP state reported by `ss`, for example `ESTAB`          |
| `destinations[].ack_age_seconds`   | Seconds since the last ACK progress                      |
| `destinations[].bytes_sent`        | Bytes sent on the socket                                 |
| `destinations[].bytes_acked`       | Bytes acknowledged by the remote TCP stack               |
| `destinations[].send_queue_bytes`  | Unsent bytes in the socket send queue                    |
| `destinations[].unacked_segments`  | Unacknowledged TCP segments                              |
| `destinations[].retransmissions`   | TCP retransmissions                                      |
| `destinations[].error`             | See the codes below                                      |

Per-destination error codes:

| Code                  | Meaning                                                       |
| --------------------- | ------------------------------------------------------------- |
| `ack_stalled`         | No ACK progress within the warning or down threshold          |
| `no_socket`           | ODR-AudioEnc has no TCP socket to this destination            |
| `tcp_not_established` | The socket exists but is not in the `ESTAB` state             |
| `invalid_destination` | The destination URL has no valid host or port                 |
| `monitor_failed`      | The monitor did not return a result for this destination      |

### How the ACK monitor works

The monitor is a shell script in `bin/dab-tcp-ack-monitor`. Liquidsoap runs it every `DAB_ACK_POLL_SECONDS` (minimum 0.25 seconds) for all configured destinations. The script reads the Linux TCP metrics of the ODR-AudioEnc socket for each `tcp://` destination with `ss`. UDP destinations are reported as `unmonitored`.

A destination makes ACK progress when `bytes_acked` grows between two polls. The destination is `starting` while it has no progress yet and the connection is younger than `DAB_ACK_STARTUP_GRACE_SECONDS`. It is `ok` when the last progress is at most `DAB_ACK_WARN_SECONDS` ago, `degraded` when it is at most `DAB_ACK_DOWN_SECONDS` ago, and `down` after that. The script keeps its state per destination in `/dev/shm/dab-ack-monitor/state`.

A TCP ACK proves only that the remote TCP stack received the data, so it says nothing about whether ODR-DabMux processed it.

### dab.status

The `dab.status` server command shows the same state as text. The first line is the overall status. When there is an aggregate error, the line ends with `: <code>`. Each destination line shows the destination, its status, its error code if there is one, and the TCP counters when the socket is connected:

```text
ok
tcp://primary.example.com:9001 ok ack_age=0s bytes_sent=123456 bytes_acked=123457 send_queue=0 unacked=0 retrans=0
```

After an encoder failure, for example, it shows:

```text
down: encoder_error
tcp://primary.example.com:9001 down no_socket
```

## outputs.hls

| Field                            | Meaning                                                            |
| -------------------------------- | ------------------------------------------------------------------ |
| `status`                         | `disabled`, `starting`, `ok`, or `degraded`                        |
| `local.status`                   | Health of the local writer                                         |
| `local.error`                    | See the error code summary                                         |
| `local.playlist_count`           | Playlists in `HLS_DIR`                                             |
| `local.segment_count`            | Segments in `HLS_DIR`                                              |
| `local.update_age_seconds`       | Seconds since a local playlist was last written                    |
| `mirror.status`                  | Health of the Bunny mirror                                         |
| `mirror.error`                   | See the error code summary                                         |
| `mirror.host`                    | Bunny Storage endpoint host                                        |
| `mirror.storage_zone`            | `HLS_BUNNY_STORAGE_ZONE`                                           |
| `mirror.published_age_seconds`   | Age of the published audio, see below                              |
| `mirror.recovered_uploads`       | Uploads that succeeded after earlier failed attempts               |
| `mirror.expired_segments`        | Segments that left the live window without a confirmed upload      |
| `mirror.pending_segments`        | Segments in the local playlists that are not confirmed remotely    |
| `mirror.pending_playlists`       | Local playlists that differ from the published ones                |

`status` is `degraded` when the writer or the mirror is degraded, `starting` when one of them has not made progress yet, and `ok` otherwise.

### Stall detection

The writer and the mirror both report `stalled` after `max(15.0, HLS_SEGMENT_DURATION * 4.0)` seconds without progress, which is 16 seconds with the defaults. For the writer, progress is a written playlist. For the mirror, it is a `published_age_seconds` below the threshold, so a mirror stall means that the published audio is old, whether a Bunny request failed or an upload was slow. A writer stall always causes a mirror stall, so when both report `stalled`, check the writer first. [HLS operations](hls-operations.md#health) explains the threshold in detail.

### Mirror counters

- `published_age_seconds` is the age of the newest confirmed segment of the variant that is furthest behind. The age is measured from the generation time in the segment name. The value is `null` until every variant has a published playlist with a known segment time. The static main playlist is not counted.
- `pending_segments` and `pending_playlists` are counted from the current local playlists every second. Uploads that are running are included. The main playlist counts as one pending playlist until it is published.
- `recovered_uploads` counts uploads that succeeded after one or more failed attempts for the same object name. The playlist may have moved on in the meantime.
- `expired_segments` counts segments that left the live playlist of a worker without a confirmed upload. This includes segments that were never tried because an earlier segment in the same playlist failed. The counter records missing confirmations, so an expired segment may still exist on the remote side.

Both counters reset when the process restarts.

### hls.status

The `hls.status` server command shows the overall HLS status, followed by `: local=<code>` and `mirror=<code>` when there are errors. See [HLS operations](hls-operations.md) for the mechanics behind these values.

## Error code summary

| Field                                                | Codes                                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `studio_inputs[].error`                              | `disconnected`, `silent`                                                                                                |
| `studio_inputs[].srt.connections[].statistics_error` | `statistics_unavailable`                                                                                                |
| `outputs.dab.error`                                  | `encoder_error`, `monitor_failed`                                                                                       |
| `outputs.dab.destinations[].error`                   | `ack_stalled`, `no_socket`, `tcp_not_established`, `invalid_destination`, `monitor_failed`                              |
| `outputs.hls.local.error`                            | `dir_missing`, `dir_not_writable`, `clock_error`, `stalled`                                                             |
| `outputs.hls.mirror.error`                           | `listing_failed`, `upload_failed`, `delete_failed`, `read_failed`, `local_file_missing`, `worker_failed`, `stalled`     |

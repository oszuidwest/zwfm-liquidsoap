# Minimal settings and dependencies required to load the studio status helpers.
let SRT_PASSPHRASE = "test-passphrase"
let SILENCE_SWITCH_SECONDS = 15.0
let AUDIO_VALID_SECONDS = 15.0
let SILENCE_THRESHOLD = -40.0

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"
%include "../conf/lib/30_silence.liq"
%include "../conf/lib/41_source_studio.liq"

assert(null.get(studio_level_dbfs(true, 1.0)) == 0.0)
assert(null.get(studio_level_dbfs(true, 0.1)) == -20.0)
assert(null.get(studio_level_dbfs(true, 0.0)) == studio_level_floor_dbfs)
assert(null.get(studio_level_dbfs(true, 0.0000001)) == studio_level_floor_dbfs)
assert(not null.defined(studio_level_dbfs(false, 1.0)))

let with_statistics =
  studio_srt_connection(
    id="studio_a",
    "192.0.2.1",
    fun () ->
      {
        msRcvTsbPdDelay = 2000,
        msRcvBuf = 1876,
        msRTT = 20.5,
        pktRcvDropTotal = 0
      }
  )
assert(null.get(with_statistics.latency_ms) == 2000)
assert(null.get(with_statistics.rtt_ms) == 20.5)
assert(not null.defined(with_statistics.statistics_error))

# A failed statistics read keeps the connection, with only the metrics missing.
let without_statistics =
  studio_srt_connection(
    id="studio_a",
    "192.0.2.1",
    fun () ->
      error.raise(
        error.not_found,
        "socket closed"
      )
  )
assert(null.get(without_statistics.peer) == "192.0.2.1")
assert(not null.defined(without_statistics.latency_ms))
assert(not null.defined(without_statistics.dropped_packets_total))
assert(
  null.get(without_statistics.statistics_error) ==
    "socket closed"
)

shutdown()

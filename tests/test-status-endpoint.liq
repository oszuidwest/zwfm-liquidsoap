# Minimal state required to load and exercise the shared HTTP endpoint module.
let STATION_ID = "test"
let STREAM_METADATA_PORT = 7000
let STREAM_METADATA_BEARER_TOKEN = ""

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"

let dab_ack_status = ref("disabled\nDAB+ output is disabled")

def dab_ack_snapshot_state(snapshot) =
  let (state, _) = string.split.first(separator="\n", snapshot)
  string.trim(state)
end

let hls_health_status = ref("disabled")
let hls_health_degraded_since = ref(0.0)
let hls_health_retry_at = ref(0.0)
let hls_health_retry_delay = ref(0.0)

def hls_status_snapshot() =
  hls_health_status()
end

def hls_retry_snapshot() =
  {
    degraded_since = hls_health_degraded_since(),
    retry_at = hls_health_retry_at(),
    retry_delay = hls_health_retry_delay()
  }
end

%include "../conf/lib/42_metadata.liq"

let fallback_source = blank(id="test_fallback")
let sources = [("fallback", fallback_source)]

let disabled_snapshot = status_snapshot(fallback_source, sources=sources)
assert(disabled_snapshot.outputs.hls.status == "disabled")
assert(disabled_snapshot.outputs.hls.detail == "")
assert(disabled_snapshot.outputs.hls.retry_in == 0.0)
ignore(json.stringify(compact=true, disabled_snapshot))

hls_health_status := "degraded: test failure"
hls_health_degraded_since := time() - 10.0
hls_health_retry_at := time() + 5.0
hls_health_retry_delay := 5.0
let degraded_snapshot = status_snapshot(fallback_source, sources=sources)
assert(degraded_snapshot.outputs.hls.status == "degraded")
assert(degraded_snapshot.outputs.hls.detail == "test failure")
assert(degraded_snapshot.outputs.hls.retry_in > 0.0)
ignore(json.stringify(compact=true, degraded_snapshot))

shutdown()

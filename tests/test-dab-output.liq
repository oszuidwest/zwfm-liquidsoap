# Load the DAB helpers with minimal configuration.
let DAB_ACK_POLL_SECONDS = 1.0
let DAB_ACK_WARN_SECONDS = 5
let DAB_ACK_DOWN_SECONDS = 15
let DAB_ACK_STARTUP_GRACE_SECONDS = 10
let DAB_ACK_MONITOR_ENABLED = true
let DAB_BITRATE = ""
let DAB_EDI_DESTINATIONS =
  "tcp://192.0.2.10:9171, udp://192.0.2.11:9172"
let DAB_METADATA_SOCKET = ""
let DAB_METADATA_SIZE = ""

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"
%include "../conf/lib/61_output_dab.liq"

assert(
  dab_edi_args(
    " tcp://one.example:9001 , tcp://two.example:9002 "
  ) ==
    ["--edi=tcp://one.example:9001", "--edi=tcp://two.example:9002"]
)

def assert_invalid_destinations(destinations) =
  let rejected =
    try
      ignore(dab_edi_args(destinations))
      false
    catch _ do
      true
    end
  assert(rejected)
end

assert_invalid_destinations("tcp://one.example:9001,,tcp://two.example:9002")
assert_invalid_destinations("tcp://one.example:9001,")

# Preserve the trailing empty error field.
let ack_snapshot =
  dab_parse_ack_monitor(
    "degraded\ntcp://192.0.2.20:9175\tdown\t\t\t\t\t\t\t\tno_socket\ntcp://192.0.2.30:9177\tdegraded\tESTAB\t7\t300\t200\t0\t0\t0\tack_stalled\ntcp://192.0.2.10:9171\tok\tESTAB\t0\t100\t101\t1745\t1\t0\t\n"
  )
assert(ack_snapshot.status == "degraded")
assert(ack_snapshot.detail == "")
assert(list.length(ack_snapshot.destinations) == 3)
let healthy_destination = list.nth(ack_snapshot.destinations, 2)
assert(healthy_destination.destination == "tcp://192.0.2.10:9171")
assert(healthy_destination.status == "ok")
assert(healthy_destination.tcp_state == "ESTAB")
assert(null.get(healthy_destination.ack_age_seconds) == 0)
assert(null.get(healthy_destination.bytes_sent) == 100)
assert(null.get(healthy_destination.bytes_acked) == 101)
assert(null.get(healthy_destination.send_queue_bytes) == 1745)
assert(null.get(healthy_destination.unacked_segments) == 1)
assert(null.get(healthy_destination.retransmissions) == 0)
assert(not null.defined(healthy_destination.error))
let down_destination = list.nth(ack_snapshot.destinations, 0)
assert(down_destination.status == "down")
assert(not null.defined(down_destination.ack_age_seconds))
assert(not null.defined(down_destination.tcp_state))
assert(null.get(down_destination.error) == "no_socket")

let stalled_destination = list.nth(ack_snapshot.destinations, 1)
assert(null.get(stalled_destination.error) == "ack_stalled")

# Monitor-level failures are not destination records.
let failed_snapshot =
  dab_parse_ack_monitor(
    "down\nmonitor error: ss is not available\n"
  )
assert(list.is_empty(failed_snapshot.destinations))
assert(
  failed_snapshot.detail ==
    "monitor error: ss is not available"
)

# Aggregate failures retain configured destinations.
dab_set_ack_status(
  "down",
  failure="monitor_failed",
  detail=failed_snapshot.detail
)
assert(null.get(dab_ack_status().error) == "monitor_failed")
let placeholders = dab_ack_status().destinations
assert(
  list.map(fun (d) -> d.destination, placeholders) ==
    ["tcp://192.0.2.10:9171", "udp://192.0.2.11:9172"]
)
assert(list.for_all(fun (d) -> d.status == "down", placeholders))
assert(
  list.for_all(fun (d) -> null.get(d.error) == "monitor_failed", placeholders)
)
assert(list.for_all(fun (d) -> not null.defined(d.tcp_state), placeholders))
assert(
  dab_status_text() ==
    "down: monitor_failed\ntcp://192.0.2.10:9171 down \
     monitor_failed\nudp://192.0.2.11:9172 down monitor_failed"
)

# Per-destination errors leave the aggregate error null.
dab_set_ack_status(ack_snapshot.status, destinations=ack_snapshot.destinations)
assert(not null.defined(dab_ack_status().error))
assert(list.length(dab_ack_status().destinations) == 3)
assert(
  dab_status_text() ==
    "degraded\ntcp://192.0.2.20:9175 down no_socket\ntcp://192.0.2.30:9177 \
     degraded ack_stalled ack_age=7s bytes_sent=300 bytes_acked=200 send_queue=0 \
     unacked=0 retrans=0\ntcp://192.0.2.10:9171 ok ack_age=0s bytes_sent=100 \
     bytes_acked=101 send_queue=1745 unacked=1 retrans=0"
)

# Encoder failures override ACK health during the hold period.
dab_encoder_error_at := time()
dab_set_ack_status(ack_snapshot.status, destinations=ack_snapshot.destinations)
assert(dab_health().status == "down")
assert(null.get(dab_health().error) == "encoder_error")
assert(
  string.contains(
    prefix="down: encoder_error\n",
    dab_status_text()
  )
)
dab_encoder_error_at := time() - dab_encoder_error_hold_seconds
assert(dab_health().status == "degraded")
assert(not null.defined(dab_health().error))

dab_set_ack_status("unmonitored")
assert(
  dab_status_text() ==
    "unmonitored\ntcp://192.0.2.10:9171 unmonitored\nudp://192.0.2.11:9172 \
     unmonitored"
)

dab_set_ack_status("starting")
assert(not null.defined(dab_ack_status().error))
assert(
  list.for_all(
    fun (d) -> d.status == "starting" and not null.defined(d.error),
    dab_ack_status().destinations
  )
)

let encoded_ack_snapshot = json.stringify(compact=true, ack_snapshot)
assert(string.contains(substring="\"ack_age_seconds\":0", encoded_ack_snapshot))
assert(
  string.contains(substring="\"ack_age_seconds\":null", encoded_ack_snapshot)
)
let encoded_destination = json.stringify(compact=true, healthy_destination)
assert(not string.contains(substring="\"detail\"", encoded_destination))

shutdown()

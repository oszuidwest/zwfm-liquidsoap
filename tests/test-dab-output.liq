# Load the DAB helpers with minimal configuration.
let DAB_ACK_POLL_SECONDS = 1.0
let DAB_ACK_WARN_SECONDS = 5
let DAB_ACK_DOWN_SECONDS = 15
let DAB_ACK_STARTUP_GRACE_SECONDS = 10
let DAB_ACK_MONITOR_ENABLED = true
let DAB_BITRATE = ""
let DAB_EDI_DESTINATIONS = ""
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

# The connected record comes last, so its empty message field ends the output.
let ack_snapshot =
  dab_parse_ack_monitor(
    "degraded\ntcp://192.0.2.20:9175\tdown\t\t\t\t\t\t\t\tno AudioEnc TCP \
     socket\ntcp://192.0.2.30:9177\tdegraded\tESTAB\t7\t300\t200\t0\t0\t0\tno \
     acknowledgement progress for \
     7s\ntcp://192.0.2.10:9171\tok\tESTAB\t0\t100\t101\t1745\t1\t0\t\n"
  )
assert(ack_snapshot.status == "degraded")
assert(not null.defined(ack_snapshot.error))
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
assert(not null.defined(healthy_destination.reason))
assert(not null.defined(healthy_destination.error))
let down_destination = list.nth(ack_snapshot.destinations, 0)
assert(down_destination.status == "down")
assert(not null.defined(down_destination.ack_age_seconds))
assert(
  null.get(down_destination.error) ==
    "no AudioEnc TCP socket"
)
assert(not null.defined(down_destination.reason))

let stalled_destination = list.nth(ack_snapshot.destinations, 1)
assert(
  null.get(stalled_destination.error) ==
    "no acknowledgement progress for 7s"
)

# A healthy destination's message is a reason, not an error.
let starting_destination =
  dab_parse_ack_record(
    "tcp://192.0.2.40:9179\tstarting\t\t\t\t\t\t\t\tno AudioEnc TCP socket"
  )
assert(not null.defined(starting_destination.error))
assert(
  null.get(starting_destination.reason) ==
    "no AudioEnc TCP socket"
)

# Non-record lines become the aggregate error.
let failed_snapshot =
  dab_parse_ack_monitor(
    "down\nmonitor error: ss is not available\n"
  )
assert(failed_snapshot.status == "down")
assert(
  null.get(failed_snapshot.error) ==
    "monitor error: ss is not available"
)
assert(list.is_empty(failed_snapshot.destinations))

# dab.status renders the structured state.
dab_set_ack_status(
  ack_snapshot.status,
  message=ack_snapshot.error,
  destinations=ack_snapshot.destinations
)
assert(
  dab_status_text() ==
    "degraded\ntcp://192.0.2.20:9175 down (no AudioEnc TCP \
     socket)\ntcp://192.0.2.30:9177 degraded (no acknowledgement progress for \
     7s)\ntcp://192.0.2.10:9171 ok (TCP ESTAB, ack_age=0s, bytes_sent=100, \
     bytes_acked=101, send_queue=1745, unacked=1, retrans=0)"
)
assert(not null.defined(dab_health().error))

# An encoder error outlives monitor ticks until the hold expires.
dab_encoder_error :=
  {
    message =
      "DAB+ encoder error: exited",
    at = time()
  }
dab_set_ack_status(
  ack_snapshot.status,
  message=ack_snapshot.error,
  destinations=ack_snapshot.destinations
)
assert(dab_health().status == "down")
assert(
  null.get(dab_health().error) ==
    "DAB+ encoder error: exited"
)
assert(list.length(dab_health().destinations) == 3)
assert(
  string.contains(
    prefix="down: DAB+ encoder error: exited\ntcp://192.0.2.20:9175 down",
    dab_status_text()
  )
)
dab_encoder_error :=
  {...dab_encoder_error(), at = time() - dab_encoder_error_hold_seconds - 1.0}
assert(dab_health().status == "degraded")

# Without the monitor, an expired encoder error falls back to unmonitored.
dab_set_ack_status(
  "unmonitored",
  message="TCP ACK monitoring is disabled"
)
assert(dab_health().status == "unmonitored")
assert(not null.defined(dab_health().error))
assert(
  dab_status_text() ==
    "unmonitored: TCP ACK monitoring is disabled"
)

let encoded_ack_snapshot = json.stringify(compact=true, ack_snapshot)
assert(string.contains(substring="\"ack_age_seconds\":0", encoded_ack_snapshot))
assert(
  string.contains(substring="\"ack_age_seconds\":null", encoded_ack_snapshot)
)

shutdown()

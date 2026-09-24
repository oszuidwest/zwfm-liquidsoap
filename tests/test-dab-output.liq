# Minimal settings required to load the DAB output module.
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

# The connected record comes last, so its empty reason field ends the output.
let ack_snapshot =
  dab_parse_ack_monitor(
    "degraded\ntcp://192.0.2.20:9175\tdown\t\t\t\t\t\t\t\tno AudioEnc TCP \
     socket\ntcp://192.0.2.30:9177\tdegraded\tESTAB\t7\t300\t200\t0\t0\t0\t\ntcp://192.0.2.10:9171\tok\tESTAB\t0\t100\t101\t1745\t1\t0\t\n"
  )
assert(ack_snapshot.status == "degraded")
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
assert(
  null.get(down_destination.error) ==
    "no AudioEnc TCP socket"
)

let stalled_destination = list.nth(ack_snapshot.destinations, 1)
assert(
  null.get(stalled_destination.error) ==
    "No acknowledgement progress for 7s"
)

# A destination still in its startup grace is healthy despite a reason.
let (_, starting_destination) =
  dab_parse_ack_line(
    "tcp://192.0.2.40:9179\tstarting\t\t\t\t\t\t\t\tno AudioEnc TCP socket"
  )
assert(not null.defined(null.get(starting_destination).error))

assert(
  string.contains(
    substring="tcp://192.0.2.20:9175 down (no AudioEnc TCP socket)",
    ack_snapshot.detail
  )
)
assert(
  string.contains(
    substring="tcp://192.0.2.10:9171 ok (TCP ESTAB, ack_age=0s, bytes_sent=100, \
     bytes_acked=101, send_queue=1745, unacked=1, retrans=0)",
    ack_snapshot.detail
  )
)

# Only failures without destination records surface as the output's error.
dab_set_ack_status(
  "down",
  "DAB+ encoder error: exited"
)
assert(
  null.get(dab_ack_status().error) ==
    "DAB+ encoder error: exited"
)
dab_set_ack_status(
  ack_snapshot.status,
  ack_snapshot.detail,
  destinations=ack_snapshot.destinations
)
assert(not null.defined(dab_ack_status().error))
dab_set_ack_status(
  "starting",
  "Waiting for AudioEnc TCP acknowledgements"
)
assert(not null.defined(dab_ack_status().error))

let encoded_ack_snapshot = json.stringify(compact=true, ack_snapshot)
assert(string.contains(substring="\"ack_age_seconds\":0", encoded_ack_snapshot))
assert(
  string.contains(substring="\"ack_age_seconds\":null", encoded_ack_snapshot)
)
let encoded_destination = json.stringify(compact=true, healthy_destination)
assert(not string.contains(substring="\"detail\"", encoded_destination))

shutdown()

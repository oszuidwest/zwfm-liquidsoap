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
shutdown()

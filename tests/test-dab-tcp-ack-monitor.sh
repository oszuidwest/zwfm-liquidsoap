#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MONITOR="${REPO_ROOT}/bin/dab-tcp-ack-monitor"
TEST_DIR=$(mktemp -d)
FAKE_SS_DIR="${TEST_DIR}/ss"
STATE_DIR="${TEST_DIR}/state"
FAKE_SS="${TEST_DIR}/fake-ss"

cleanup()
{
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT

mkdir -p -- "${FAKE_SS_DIR}"

cat > "${FAKE_SS}" <<'EOF'
#!/bin/sh
for argument in "$@"; do
  case ${argument} in
    :*)
      port=${argument#:}
      if [ -r "${FAKE_SS_DIR}/${port}" ]; then
        cat "${FAKE_SS_DIR}/${port}"
      fi
      exit 0
      ;;
  esac
done
EOF
chmod +x "${FAKE_SS}"

monitor()
{
  now=$1
  destinations=$2
  ack_warn_seconds=${3:-5}
  ack_down_seconds=${4:-15}
  startup_grace_seconds=${5:-10}
  DAB_ACK_MONITOR_NOW=${now} \
    FAKE_SS_DIR=${FAKE_SS_DIR} \
    SS_BIN=${FAKE_SS} \
    "${MONITOR}" \
      --state-dir "${STATE_DIR}" \
      --destinations "${destinations}" \
      --ack-warn-seconds "${ack_warn_seconds}" \
      --ack-down-seconds "${ack_down_seconds}" \
      --startup-grace-seconds "${startup_grace_seconds}"
}

assert_status()
{
  expected=$1
  output=$2
  actual=$(printf '%s\n' "${output}" | sed -n '1p')
  if [ "${actual}" != "${expected}" ]; then
    printf 'Expected status %s, got %s:\n%s\n' "${expected}" "${actual}" "${output}" >&2
    exit 1
  fi
}

write_socket()
{
  port=$1
  sent=$2
  acked=$3
  source_port=${4:-41000}
  cat > "${FAKE_SS_DIR}/${port}" <<EOF
ESTAB 0 0 10.0.0.2:${source_port} 192.0.2.10:${port} users:(("odr-audioenc",pid=4242,fd=5)) cubic bytes_sent:${sent} bytes_acked:${acked} unacked:0 retrans:0/0
EOF
}

DESTINATION=tcp://192.0.2.10:9171

write_socket 9171 100 101
output=$(monitor 100 "${DESTINATION}")
assert_status ok "${output}"

output=$(monitor 106 "${DESTINATION}")
assert_status degraded "${output}"

output=$(monitor 116 "${DESTINATION}")
assert_status down "${output}"

write_socket 9171 200 201
output=$(monitor 117 "${DESTINATION}")
assert_status ok "${output}"

write_socket 9175 0 0
output=$(monitor 118 "${DESTINATION},tcp://192.0.2.20:9175")
assert_status degraded "${output}"

rm -f -- "${FAKE_SS_DIR}/9171"
output=$(monitor 119 "${DESTINATION}")
assert_status down "${output}"

rm -rf -- "${STATE_DIR}"
write_socket 9171 100 1
output=$(monitor 200 "${DESTINATION}" 5 15 2)
assert_status starting "${output}"
output=$(monitor 203 "${DESTINATION}" 5 15 2)
assert_status degraded "${output}"

rm -rf -- "${STATE_DIR}"
write_socket 9171 100 101 41000
output=$(monitor 300 "${DESTINATION}")
assert_status ok "${output}"
write_socket 9171 0 1 42000
output=$(monitor 400 "${DESTINATION}")
assert_status starting "${output}"
output=$(monitor 411 "${DESTINATION}")
assert_status degraded "${output}"

rm -rf -- "${STATE_DIR}"
mkdir -p -- "${STATE_DIR}"
printf '%s\n' \
  '10.0.0.2:41000>192.0.2.10:9171 1 200 100' \
  > "${STATE_DIR}/destination-1.state"
output=$(monitor 100 "${DESTINATION}")
assert_status starting "${output}"

printf '%s\n' \
  '10.0.0.2:41000>192.0.2.10:9171 1 0 200' \
  > "${STATE_DIR}/destination-1.state"
output=$(monitor 100 "${DESTINATION}")
assert_status starting "${output}"
output=$(monitor 111 "${DESTINATION}")
assert_status degraded "${output}"

rm -rf -- "${STATE_DIR}"
output=$(monitor 120 udp://192.0.2.10:9171)
assert_status unmonitored "${output}"

printf '%s\n' 'dab-tcp-ack-monitor tests passed'

#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MONITOR="${REPO_ROOT}/bin/dab-tcp-ack-monitor"
TEST_DIR=$(mktemp -d)
FAKE_SS_DIR="${TEST_DIR}/ss"
PID_FILE="${TEST_DIR}/audioenc.pid"
STATE_DIR="${TEST_DIR}/state"
FAKE_SS="${TEST_DIR}/fake-ss"

cleanup()
{
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT

mkdir -p -- "${FAKE_SS_DIR}"
printf '%s\n' "$$" > "${PID_FILE}"

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
  DAB_ACK_MONITOR_NOW=${now} \
    FAKE_SS_DIR=${FAKE_SS_DIR} \
    SS_BIN=${FAKE_SS} \
    "${MONITOR}" \
      --pid-file "${PID_FILE}" \
      --state-dir "${STATE_DIR}" \
      --destinations "${destinations}" \
      --ack-warn-seconds 5 \
      --ack-down-seconds 15 \
      --startup-grace-seconds 10
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
  send_queue=${4:-0}
  cat > "${FAKE_SS_DIR}/${port}" <<EOF
ESTAB 0 ${send_queue} 10.0.0.2:41000 192.0.2.10:${port} users:(("odr-audioenc",pid=$$,fd=5)) cubic bytes_sent:${sent} bytes_acked:${acked} unacked:0 retrans:0/0
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

rm -f -- "${PID_FILE}"
output=$(monitor 119 "${DESTINATION}")
assert_status down "${output}"

rm -rf -- "${STATE_DIR}"
mkdir -p -- "${STATE_DIR}"
printf '%s\n' "$$" > "${PID_FILE}"
output=$(monitor 120 udp://192.0.2.10:9171)
assert_status unmonitored "${output}"

printf '%s\n' 'dab-tcp-ack-monitor tests passed'

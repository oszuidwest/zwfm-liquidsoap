#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SUPERVISOR="${REPO_ROOT}/bin/odr-audioenc-supervisor"
TEST_DIR=$(mktemp -d)
FAKE_ENCODER="${TEST_DIR}/fake-encoder"
PID_FILE="${TEST_DIR}/audioenc.pid"
CAPTURE_FILE="${TEST_DIR}/stdin"
ARGS_FILE="${TEST_DIR}/args"
ENCODER_PID_FILE="${TEST_DIR}/encoder.pid"

cleanup()
{
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT

cat > "${FAKE_ENCODER}" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" > "${ENCODER_PID_FILE}"
printf '%s\n' "$*" > "${ARGS_FILE}"
cat > "${CAPTURE_FILE}"
exit 7
EOF
chmod +x "${FAKE_ENCODER}"

set +e
printf '%s' 'audio-stream' | \
  CAPTURE_FILE=${CAPTURE_FILE} \
  ARGS_FILE=${ARGS_FILE} \
  ENCODER_PID_FILE=${ENCODER_PID_FILE} \
  ODR_AUDIOENC_BIN=${FAKE_ENCODER} \
  ODR_AUDIOENC_PID_FILE=${PID_FILE} \
  "${SUPERVISOR}" --fake-argument
exit_status=$?
set -e

if [ "${exit_status}" -ne 7 ]; then
  printf 'Expected exit status 7, got %s\n' "${exit_status}" >&2
  exit 1
fi

if [ "$(cat "${CAPTURE_FILE}")" != 'audio-stream' ]; then
  printf '%s\n' 'Supervisor did not forward stdin' >&2
  exit 1
fi

if [ "$(cat "${ARGS_FILE}")" != '--fake-argument' ]; then
  printf '%s\n' 'Supervisor did not forward arguments' >&2
  exit 1
fi

if [ "$(cat "${PID_FILE}")" != "$(cat "${ENCODER_PID_FILE}")" ]; then
  printf '%s\n' 'PID file does not match the encoder PID' >&2
  exit 1
fi

printf '%s\n' 'odr-audioenc-supervisor tests passed'

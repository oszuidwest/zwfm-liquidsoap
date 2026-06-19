#!/usr/bin/env bash
set -euo pipefail

BASH_FUNCTIONS_REF="main"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/${BASH_FUNCTIONS_REF}/common-functions.sh"
FUNCTIONS_LIB_PATH=$(mktemp)
STEREO_TOOL_ZIP_PATH=$(mktemp)
STEREO_TOOL_PLUGIN_TMP=$(mktemp)

trap 'rm -f "${FUNCTIONS_LIB_PATH}" "${STEREO_TOOL_ZIP_PATH}" "${STEREO_TOOL_PLUGIN_TMP}"' EXIT

clear || true

if ! command -v curl >/dev/null 2>&1; then
  echo "*** curl is required to download the functions library. ***"
  exit 1
fi

if ! curl -fsSL -o "${FUNCTIONS_LIB_PATH}" "${FUNCTIONS_LIB_URL}"; then
  echo "*** Failed to download functions library. Please check your network connection. ***"
  exit 1
fi

# shellcheck source=/dev/null
source "${FUNCTIONS_LIB_PATH}"

# Define base variables
INSTALL_DIR="/opt/liquidsoap"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_BASE="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/${GITHUB_BRANCH}"

# Docker files
DOCKER_COMPOSE_URL="${GITHUB_BASE}/docker-compose.yml"
DOCKER_COMPOSE_PATH="${INSTALL_DIR}/docker-compose.yml"

# Liquidsoap configuration
LIQUIDSOAP_CONFIG_URL_ZUIDWEST="${GITHUB_BASE}/conf/zuidwest.liq"
LIQUIDSOAP_CONFIG_URL_RUCPHEN="${GITHUB_BASE}/conf/rucphen.liq"
LIQUIDSOAP_CONFIG_URL_BREDANU="${GITHUB_BASE}/conf/bredanu.liq"
LIQUIDSOAP_CONFIG_PATH="${INSTALL_DIR}/scripts/radio.liq"

LIQUIDSOAP_ENV_URL_ZUIDWEST="${GITHUB_BASE}/.env.zuidwest.example"
LIQUIDSOAP_ENV_URL_RUCPHEN="${GITHUB_BASE}/.env.rucphen.example"
LIQUIDSOAP_ENV_URL_BREDANU="${GITHUB_BASE}/.env.bredanu.example"
LIQUIDSOAP_ENV_PATH="${INSTALL_DIR}/.env"

# Liquidsoap library files
LIQUIDSOAP_LIB_DIR="${INSTALL_DIR}/scripts/lib"
LIQUIDSOAP_LIB_URL_BASE="${GITHUB_BASE}/conf/lib"
LIQUIDSOAP_LIB_FILES=(
  "00_settings.liq"
  "10_logging.liq"
  "20_state.liq"
  "30_silence.liq"
  "40_source_fallback.liq"
  "41_source_studio.liq"
  "50_processing.liq"
  "60_output_icecast.liq"
  "61_output_dab.liq"
  "80_server.liq"
  "90_radio.liq"
)

AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"
AUDIO_FALLBACK_PATH="${INSTALL_DIR}/audio/fallback.ogg"

# StereoTool configuration
STEREO_TOOL_VERSION="1075"
STEREO_TOOL_BASE_URL="https://download.thimeo.com"
STEREO_TOOL_ZIP_URL="${STEREO_TOOL_BASE_URL}/Stereo_Tool_Generic_plugin_${STEREO_TOOL_VERSION}.zip"
STEREO_TOOL_INSTALL_DIR="${INSTALL_DIR}/stereotool"


# General configuration
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=(
  "${INSTALL_DIR}/scripts"
  "${INSTALL_DIR}/scripts/lib"
  "${INSTALL_DIR}/audio"
  "${INSTALL_DIR}/socket"
)

# Environment setup
set_colors
assert_user_privileged "root"
assert_os_linux
assert_os_64bit
assert_tool "curl" "docker" "dpkg"
OS_ARCH=$(dpkg --print-architecture)

# Configure host time settings
set_timezone "${TIMEZONE}"
set_time_sync

# Configure journald storage limits
set_journald_limits

# Display a welcome banner
cat << "EOF"
 ______     _     ___          __       _     ______ __  __
|___  /    (_)   | \ \        / /      | |   |  ____|  \/  |
   / /_   _ _  __| |\ \  /\  / /__  ___| |_  | |__  | \  / |
  / /| | | | |/ _` | \ \/  \/ / _ \/ __| __| |  __| | |\/| |
 / /_| |_| | | (_| |  \  /\  /  __/\__ \ |_  | |    | |  | |
/_____\__,_|_|\__,_|   \/  \/ \___||___/\__| |_|    |_|  |_|
EOF
echo -e "${GREEN}⎎ Liquidsoap and StereoTool Installation${NC}\n"

if [ -f "${LIQUIDSOAP_ENV_PATH}" ] || [ -f "${DOCKER_COMPOSE_PATH}" ]; then
  echo -e "${YELLOW}Existing installation detected in ${INSTALL_DIR}. Managed files will be backed up before replacement.${NC}\n"
fi

prompt_user "STATION_CONFIG" "zuidwest" "Which station configuration would you like to use? (zuidwest/rucphen/bredanu)" "str"

# Validate station configuration
if [[ ! "$STATION_CONFIG" =~ ^(zuidwest|rucphen|bredanu)$ ]]; then
  echo -e "${RED}Error: Invalid station configuration. Must be 'zuidwest', 'rucphen', or 'bredanu'.${NC}"
  exit 1
fi
prompt_user "DO_UPDATES" "y" "Would you like to perform all OS updates? (y/n)" "y/n"

if [ "${DO_UPDATES}" == "y" ]; then
  apt_update --silent
fi

# Create required directories
echo -e "${BLUE}►► Creating directories...${NC}"
for dir in "${DIRECTORIES[@]}"; do
  mkdir -p "${dir}"
done

# Backup and download configuration files
echo -e "${BLUE}►► Downloading configuration files...${NC}"

# Set configuration URL based on user choice
if [ "${STATION_CONFIG}" == "zuidwest" ]; then
  LIQUIDSOAP_CONFIG_URL="${LIQUIDSOAP_CONFIG_URL_ZUIDWEST}"
  LIQUIDSOAP_ENV_URL="${LIQUIDSOAP_ENV_URL_ZUIDWEST}"
elif [ "${STATION_CONFIG}" == "rucphen" ]; then
  LIQUIDSOAP_CONFIG_URL="${LIQUIDSOAP_CONFIG_URL_RUCPHEN}"
  LIQUIDSOAP_ENV_URL="${LIQUIDSOAP_ENV_URL_RUCPHEN}"
else
  LIQUIDSOAP_CONFIG_URL="${LIQUIDSOAP_CONFIG_URL_BREDANU}"
  LIQUIDSOAP_ENV_URL="${LIQUIDSOAP_ENV_URL_BREDANU}"
fi

if ! file_download "${LIQUIDSOAP_CONFIG_URL}" "${LIQUIDSOAP_CONFIG_PATH}" "Liquidsoap configuration for ${STATION_CONFIG}" --backup; then
  exit 1
fi

echo -e "${BLUE}►► Downloading Liquidsoap library files...${NC}"
LIB_DOWNLOAD_ARGS=()
for lib_file in "${LIQUIDSOAP_LIB_FILES[@]}"; do
  LIB_DOWNLOAD_ARGS+=("${LIQUIDSOAP_LIB_URL_BASE}/${lib_file}|${lib_file}")
done
if ! file_download -m "${LIQUIDSOAP_LIB_DIR}" "Liquidsoap library files" \
  --backup "${LIB_DOWNLOAD_ARGS[@]}"; then
  exit 1
fi

if ! file_download "${LIQUIDSOAP_ENV_URL}" "${LIQUIDSOAP_ENV_PATH}" "Liquidsoap env for ${STATION_CONFIG}" --backup; then
  exit 1
fi

if ! file_download "${DOCKER_COMPOSE_URL}" "${DOCKER_COMPOSE_PATH}" "docker-compose.yml" --backup; then
  exit 1
fi

if ! file_download "${AUDIO_FALLBACK_URL}" "${AUDIO_FALLBACK_PATH}" "audio fallback file" --backup; then
  exit 1
fi

# Always install StereoTool (whether it's used depends on STEREOTOOL_LICENSE_KEY in .env)
echo -e "${BLUE}►► Installing StereoTool...${NC}"
apt_install --silent unzip


# Create installation directory
mkdir -p "${STEREO_TOOL_INSTALL_DIR}"

# Download and install StereoTool
if ! file_download "${STEREO_TOOL_ZIP_URL}" "${STEREO_TOOL_ZIP_PATH}" "StereoTool"; then
  exit 1
fi

# Select the appropriate library based on the architecture. The StereoTool zip
# uses backslashes in member names, so ? is used as the path separator pattern.
case "${OS_ARCH}" in
  amd64)
    STEREO_TOOL_ARCHIVE_MEMBER="libStereoTool_${STEREO_TOOL_VERSION}?lib?Linux?IntelAMD?64?libStereoTool_intel64.so"
    ;;
  arm64)
    STEREO_TOOL_ARCHIVE_MEMBER="libStereoTool_${STEREO_TOOL_VERSION}?lib?Linux?ARM?64?libStereoTool_noX11_arm64.so"
    ;;
  *)
    echo -e "${RED}Unsupported architecture: ${OS_ARCH}${NC}"
    exit 1
    ;;
esac

if ! unzip -p "${STEREO_TOOL_ZIP_PATH}" "${STEREO_TOOL_ARCHIVE_MEMBER}" > "${STEREO_TOOL_PLUGIN_TMP}"; then
  echo -e "${RED}Error: Unable to extract StereoTool library for ${OS_ARCH}.${NC}"
  exit 1
fi

if [ ! -s "${STEREO_TOOL_PLUGIN_TMP}" ]; then
  echo -e "${RED}Error: Extracted StereoTool library for ${OS_ARCH} is empty.${NC}"
  exit 1
fi

install -m 644 "${STEREO_TOOL_PLUGIN_TMP}" "${STEREO_TOOL_INSTALL_DIR}/st_plugin.so"

# Write StereoTool configuration
STEREOTOOL_RC_PATH="${STEREO_TOOL_INSTALL_DIR}/.st_plugin.so.rc"
if [ -f "${STEREOTOOL_RC_PATH}" ] && ! file_backup "${STEREOTOOL_RC_PATH}"; then
  exit 1
fi
cat << EOL > "${STEREOTOOL_RC_PATH}"
[Stereo Tool Configuration]
Enable web interface=1
Whitelist=/0
EOL

# Adjust ownership for the directories (the liquidsoap container runs as UID 100 and GID 101)
echo -e "${BLUE}►► Setting ownership...${NC}"
chown -R 100:101 "${STEREO_TOOL_INSTALL_DIR}"
chown -R 100:101 "${INSTALL_DIR}/socket"

echo -e "${BLUE}►► Validating Docker Compose configuration...${NC}"
(cd "${INSTALL_DIR}" && docker compose --env-file .env config -q)

echo -e "${GREEN}Installation completed successfully for ${STATION_CONFIG} configuration!${NC}"

# Display usage instructions
echo -e "\n${BLUE}►► How to run Liquidsoap:${NC}"
echo -e "${YELLOW}Important: Before starting, make sure to edit the .env file with your configuration:${NC}"
echo -e "  ${BLUE}nano ${LIQUIDSOAP_ENV_PATH}${NC}"
echo -e ""
echo -e "${YELLOW}To start Liquidsoap:${NC}"
echo -e "  ${BLUE}cd ${INSTALL_DIR}${NC}"
echo -e "  ${BLUE}docker compose up -d${NC}"
echo -e ""
echo -e "${YELLOW}To access StereoTool GUI (if STEREOTOOL_LICENSE_KEY is set):${NC}"
echo -e "  Open http://localhost:8080 in your browser"
echo -e ""
echo -e "${YELLOW}To view logs:${NC}"
echo -e "  ${BLUE}docker compose logs -f${NC}"
echo -e ""
echo -e "${YELLOW}To stop Liquidsoap:${NC}"
echo -e "  ${BLUE}docker compose down${NC}"
echo -e ""
echo -e "${YELLOW}To control silence detection:${NC}"
echo -e "  ${BLUE}socat - UNIX-CONNECT:${INSTALL_DIR}/socket/liquidsoap.sock${NC}"
echo -e "  Enable:  ${BLUE}silence.enable${NC}"
echo -e "  Disable: ${BLUE}silence.disable${NC}"
echo -e "  Status:  ${BLUE}silence.status${NC}"

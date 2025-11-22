#!/usr/bin/env bash

# Load the functions library
FUNCTIONS_LIB_PATH=$(mktemp)
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Clean up temporary file on exit
trap 'rm -f "${FUNCTIONS_LIB_PATH}"' EXIT

# Download the functions library
if ! curl -sLo "${FUNCTIONS_LIB_PATH}" "${FUNCTIONS_LIB_URL}"; then
  echo -e "*** Failed to download the functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
# shellcheck source=/dev/null
source "${FUNCTIONS_LIB_PATH}"

# Define base variables
INSTALL_DIR="/opt/liquidsoap"
GITHUB_BASE="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main"

# Docker files
DOCKER_COMPOSE_URL="${GITHUB_BASE}/docker-compose.yml"
DOCKER_COMPOSE_PATH="${INSTALL_DIR}/docker-compose.yml"

# Liquidsoap configuration
LIQUIDSOAP_CONFIG_URL_ZUIDWEST="${GITHUB_BASE}/conf/zuidwest.liq"
LIQUIDSOAP_CONFIG_URL_RUCPHEN="${GITHUB_BASE}/conf/rucphen.liq"
LIQUIDSOAP_CONFIG_URL_BREDANU="${GITHUB_BASE}/conf/bredanu.liq"
LIQUIDSOAP_CONFIG_PATH="${INSTALL_DIR}/scripts/radio.liq"

# Liquidsoap library files
LIQUIDSOAP_LIB_DIR="${INSTALL_DIR}/scripts/lib"
LIQUIDSOAP_LIB_DEFAULTS_URL="${GITHUB_BASE}/conf/lib/defaults.liq"
LIQUIDSOAP_LIB_STUDIO_INPUTS_URL="${GITHUB_BASE}/conf/lib/studio_inputs.liq"
LIQUIDSOAP_LIB_ICECAST_OUTPUTS_URL="${GITHUB_BASE}/conf/lib/icecast_outputs.liq"

LIQUIDSOAP_ENV_URL_ZUIDWEST="${GITHUB_BASE}/.env.zuidwest.example"
LIQUIDSOAP_ENV_URL_RUCPHEN="${GITHUB_BASE}/.env.rucphen.example"
LIQUIDSOAP_ENV_URL_BREDANU="${GITHUB_BASE}/.env.bredanu.example"
LIQUIDSOAP_ENV_PATH="${INSTALL_DIR}/.env"

# Liquidsoap library files
LIQUIDSOAP_LIB_DIR="${INSTALL_DIR}/scripts/lib"
LIQUIDSOAP_LIB_DEFAULTS_URL="${GITHUB_BASE}/conf/lib/defaults.liq"
LIQUIDSOAP_LIB_STUDIO_INPUTS_URL="${GITHUB_BASE}/conf/lib/studio_inputs.liq"
LIQUIDSOAP_LIB_ICECAST_OUTPUTS_URL="${GITHUB_BASE}/conf/lib/icecast_outputs.liq"
LIQUIDSOAP_LIB_STEREOTOOL_URL="${GITHUB_BASE}/conf/lib/stereotool.liq"
LIQUIDSOAP_LIB_DAB_OUTPUT_URL="${GITHUB_BASE}/conf/lib/dab_output.liq"

AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"
AUDIO_FALLBACK_PATH="${INSTALL_DIR}/audio/fallback.ogg"

SILENCE_DETECTION_PATH="${INSTALL_DIR}/silence_detection.txt"

# StereoTool configuration
STEREO_TOOL_VERSION="1071"
STEREO_TOOL_BASE_URL="https://download.thimeo.com"
STEREO_TOOL_ZIP_URL="${STEREO_TOOL_BASE_URL}/Stereo_Tool_Generic_plugin_${STEREO_TOOL_VERSION}.zip"
STEREO_TOOL_ZIP_PATH="/tmp/stereotool.zip"
STEREO_TOOL_INSTALL_DIR="${INSTALL_DIR}/stereotool"


# General configuration
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=(
  "${INSTALL_DIR}/scripts"
  "${INSTALL_DIR}/scripts/lib"
  "${INSTALL_DIR}/audio"
)
OS_ARCH=$(dpkg --print-architecture)

# Environment setup
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone "${TIMEZONE}"

# Ensure Docker is installed
require_tool "docker"

# Display a welcome banner
clear
cat << "EOF"
 ______     _     ___          __       _     ______ __  __
|___  /    (_)   | \ \        / /      | |   |  ____|  \/  |
   / /_   _ _  __| |\ \  /\  / /__  ___| |_  | |__  | \  / |
  / /| | | | |/ _` | \ \/  \/ / _ \/ __| __| |  __| | |\/| |
 / /_| |_| | | (_| |  \  /\  /  __/\__ \ |_  | |    | |  | |
/_____\__,_|_|\__,_|   \/  \/ \___||___/\__| |_|    |_|  |_|
EOF
echo -e "${GREEN}⎎ Liquidsoap and StereoTool Installation${NC}\n"

# Prompt user for input
ask_user "STATION_CONFIG" "zuidwest" "Which station configuration would you like to use? (zuidwest/rucphen/bredanu)" "str"

# Validate station configuration
if [[ ! "$STATION_CONFIG" =~ ^(zuidwest|rucphen|bredanu)$ ]]; then
  echo -e "${RED}Error: Invalid station configuration. Must be 'zuidwest', 'rucphen', or 'bredanu'.${NC}"
  exit 1
fi
ask_user "DO_UPDATES" "y" "Would you like to perform all OS updates? (y/n)" "y/n"

if [ "${DO_UPDATES}" == "y" ]; then
  update_os silent
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

if ! download_file "${LIQUIDSOAP_CONFIG_URL}" "${LIQUIDSOAP_CONFIG_PATH}" "Liquidsoap configuration for ${STATION_CONFIG}" backup; then
  exit 1
fi

# Download library files
echo -e "${BLUE}►► Downloading Liquidsoap library files...${NC}"
if ! download_file -m "${LIQUIDSOAP_LIB_DIR}" "Liquidsoap library files" \
  "${LIQUIDSOAP_LIB_DEFAULTS_URL}:defaults.liq" \
  "${LIQUIDSOAP_LIB_STUDIO_INPUTS_URL}:studio_inputs.liq" \
  "${LIQUIDSOAP_LIB_ICECAST_OUTPUTS_URL}:icecast_outputs.liq" \
  "${LIQUIDSOAP_LIB_STEREOTOOL_URL}:stereotool.liq" \
  "${LIQUIDSOAP_LIB_DAB_OUTPUT_URL}:dab_output.liq"; then
  exit 1
fi

if ! download_file "${LIQUIDSOAP_ENV_URL}" "${LIQUIDSOAP_ENV_PATH}" "Liquidsoap env for ${STATION_CONFIG}" backup; then
  exit 1
fi

if ! download_file "${DOCKER_COMPOSE_URL}" "${DOCKER_COMPOSE_PATH}" "docker-compose.yml" backup; then
  exit 1
fi

if ! download_file "${AUDIO_FALLBACK_URL}" "${AUDIO_FALLBACK_PATH}" "audio fallback file" backup; then
  exit 1
fi

echo "1" > $SILENCE_DETECTION_PATH

# Always install StereoTool (whether it's used depends on STEREOTOOL_LICENSE_KEY in .env)
echo -e "${BLUE}►► Installing StereoTool...${NC}"
install_packages silent unzip


# Create installation directory
mkdir -p "${STEREO_TOOL_INSTALL_DIR}"

# Download and extract StereoTool
if ! download_file "${STEREO_TOOL_ZIP_URL}" "${STEREO_TOOL_ZIP_PATH}" "StereoTool"; then
  exit 1
fi
TMP_DIR=$(mktemp -d)
unzip -o "${STEREO_TOOL_ZIP_PATH}" -d "${TMP_DIR}"

# Locate the extracted directory
EXTRACTED_DIR=$(find "${TMP_DIR}" -maxdepth 1 -type d -name "libStereoTool_*" | head -n 1)
if [ ! -d "${EXTRACTED_DIR}" ]; then
  echo -e "${RED}Error: Unable to find the extracted StereoTool directory.${NC}"
  exit 1
fi

# Copy the appropriate library based on the architecture
case "${OS_ARCH}" in
  amd64)
    LIB_PATH="${EXTRACTED_DIR}/lib/Linux/IntelAMD/64/libStereoTool_intel64.so"
    ;;
  arm64)
    LIB_PATH="${EXTRACTED_DIR}/lib/Linux/ARM/64/libStereoTool_noX11_arm64.so"
    ;;
  *)
    echo -e "${RED}Unsupported architecture: ${OS_ARCH}${NC}"
    exit 1
    ;;
esac

if [ ! -f "${LIB_PATH}" ]; then
  echo -e "${RED}Error: StereoTool library not found at ${LIB_PATH}.${NC}"
  exit 1
fi

cp "${LIB_PATH}" "${STEREO_TOOL_INSTALL_DIR}/st_plugin.so"

# Clean up temporary files
rm -rf "${TMP_DIR}" "${STEREO_TOOL_ZIP_PATH}"

# Write StereoTool configuration
STEREOTOOL_RC_PATH="${STEREO_TOOL_INSTALL_DIR}/.st_plugin.so.rc"
cat << EOL > "${STEREOTOOL_RC_PATH}"
[Stereo Tool Configuration]
Enable web interface=1
Whitelist=/0
EOL

# Adjust ownership for the directories (the liquidsoap container runs as UID 100 and GID 101)
echo -e "${BLUE}►► Setting ownership for ${STEREO_TOOL_INSTALL_DIR}...${NC}"
chown -R 100:101 "${STEREO_TOOL_INSTALL_DIR}"

echo -e "${GREEN}Installation completed successfully for ${STATION_CONFIG} configuration!${NC}"

# Display usage instructions
echo -e "\n${BLUE}►► How to run Liquidsoap:${NC}"
echo -e "${YELLOW}Important: Before starting, make sure to edit the .env file with your configuration:${NC}"
echo -e "  ${CYAN}nano ${LIQUIDSOAP_ENV_PATH}${NC}"
echo -e ""
echo -e "${YELLOW}To start Liquidsoap:${NC}"
echo -e "  ${CYAN}cd ${INSTALL_DIR}${NC}"
echo -e "  ${CYAN}docker compose up -d${NC}"
echo -e ""
echo -e "${YELLOW}To access StereoTool GUI (if STEREOTOOL_LICENSE_KEY is set):${NC}"
echo -e "  Open http://localhost:8080 in your browser"
echo -e ""
echo -e "${YELLOW}To view logs:${NC}"
echo -e "  ${CYAN}docker compose logs -f${NC}"
echo -e ""
echo -e "${YELLOW}To stop Liquidsoap:${NC}"
echo -e "  ${CYAN}docker compose down${NC}"
echo -e ""
echo -e "${YELLOW}To control silence detection and fallback:${NC}"
echo -e "  Enable:  ${CYAN}echo '1' > ${SILENCE_DETECTION_PATH}${NC}"
echo -e "  Disable: ${CYAN}echo '0' > ${SILENCE_DETECTION_PATH}${NC}"
echo -e ""
echo -e "${YELLOW}When silence detection is disabled:${NC}"
echo -e "  - Studio inputs will not switch on silence"
echo -e "  - Emergency fallback file will not be used"
echo -e "  - Silent studio streams will continue playing"

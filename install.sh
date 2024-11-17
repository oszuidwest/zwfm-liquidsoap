#!/usr/bin/env bash

# Load functions library
FUNCTIONS_LIB_PATH="/tmp/functions.sh"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Download the latest version of the functions library
rm -f "${FUNCTIONS_LIB_PATH}"
if ! curl -sLo "${FUNCTIONS_LIB_PATH}" "${FUNCTIONS_LIB_URL}"; then
  echo -e "*** Failed to download functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
# shellcheck source=/tmp/functions.sh
source "${FUNCTIONS_LIB_PATH}"

# Liquidsoap configuration
LIQUIDSOAP_VERSION="2.3.0-rc2"  # TODO: On 2.3.0 check preset saving again!
LIQUIDSOAP_CONFIG_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/refs/heads/liq-230/radio.liq"
LIQUIDSOAP_CONFIG_PATH="/opt/liquidsoap/scripts/radio.liq"

AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"
AUDIO_FALLBACK_PATH="/opt/liquidsoap/audio/fallback.ogg"

DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/refs/heads/liq-230/docker-compose.yml"
DOCKER_COMPOSE_PATH="/opt/liquidsoap/docker-compose.yml"

# StereoTool configuration
STEREO_TOOL_VERSION="1021"
STEREO_TOOL_BASE_URL="https://download.thimeo.com"
STEREO_TOOL_ZIP_URL="${STEREO_TOOL_BASE_URL}/Stereo_Tool_Generic_plugin_${STEREO_TOOL_VERSION}.zip"
STEREO_TOOL_ZIP_PATH="/tmp/stereotool.zip"

# General configuration
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=(
  "/opt/liquidsoap/scripts"
  "/opt/liquidsoap/audio"
)
OS_ARCH=$(dpkg --print-architecture)

# Environment setup
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone "${TIMEZONE}"

# Check if Docker is installed
require_tool "docker"

# Display banner
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
ask_user "USE_ST" "n" "Do you want to use StereoTool for sound processing? (y/n)" "y/n"
ask_user "DO_UPDATES" "y" "Do you want to perform all OS updates? (y/n)" "y/n"

if [ "${DO_UPDATES}" == "y" ]; then
  update_os silent
fi

# Create necessary directories
echo -e "${BLUE}►► Creating directories...${NC}"
for dir in "${DIRECTORIES[@]}"; do
  mkdir -p "${dir}"
done

# Backup and download configuration files
echo -e "${BLUE}►► Downloading configuration files...${NC}"

backup_file "${LIQUIDSOAP_CONFIG_PATH}"
if ! curl -sLo "${LIQUIDSOAP_CONFIG_PATH}" "${LIQUIDSOAP_CONFIG_URL}"; then
  echo -e "${RED}Error: Failed to download Liquidsoap configuration.${NC}"
  exit 1
fi

backup_file "${DOCKER_COMPOSE_PATH}"
if ! curl -sLo "${DOCKER_COMPOSE_PATH}" "${DOCKER_COMPOSE_URL}"; then
  echo -e "${RED}Error: Failed to download docker-compose.yml.${NC}"
  exit 1
fi

if ! curl -sLo "${AUDIO_FALLBACK_PATH}" "${AUDIO_FALLBACK_URL}"; then
  echo -e "${RED}Error: Failed to download audio fallback file.${NC}"
  exit 1
fi

# Update docker-compose.yml with the correct Liquidsoap version
echo -e "${BLUE}►► Updating docker-compose.yml with the correct Liquidsoap version...${NC}"
sed -i "s|image: savonet/liquidsoap:.*|image: savonet/liquidsoap:v${LIQUIDSOAP_VERSION}|g" "${DOCKER_COMPOSE_PATH}"

if [ "${USE_ST}" == "y" ]; then
  echo -e "${BLUE}►► Installing StereoTool...${NC}"
  install_packages silent unzip

  STEREO_TOOL_DIR="/opt/liquidsoap/stereotool"
  mkdir -p "${STEREO_TOOL_DIR}/.liquidsoap.presets"

  # Download and extract StereoTool
  if ! curl -sLo "${STEREO_TOOL_ZIP_PATH}" "${STEREO_TOOL_ZIP_URL}"; then
    echo -e "${RED}Error: Failed to download StereoTool.${NC}"
    exit 1
  fi
  TMP_DIR=$(mktemp -d)
  unzip -o "${STEREO_TOOL_ZIP_PATH}" -d "${TMP_DIR}"

  # Find the extracted directory
  EXTRACTED_DIR=$(find "${TMP_DIR}" -maxdepth 1 -type d -name "libStereoTool_*" | head -n 1)
  if [ ! -d "${EXTRACTED_DIR}" ]; then
    echo -e "${RED}Error: Could not find the extracted StereoTool directory.${NC}"
    exit 1
  fi

  # Copy the library based on architecture
  case "${OS_ARCH}" in
    amd64)
      LIB_PATH="${EXTRACTED_DIR}/lib/Linux/IntelAMD/64/libStereoTool_intel64.so"
      ;;
    arm64)
      LIB_PATH="${EXTRACTED_DIR}/lib/Linux/ARM/64/libStereoTool_arm64.so"
      ;;
    *)
      echo -e "${RED}Unsupported architecture: ${OS_ARCH}${NC}"
      exit 1
      ;;
  esac

  if [ ! -f "${LIB_PATH}" ]; then
    echo -e "${RED}Error: StereoTool library not found at ${LIB_PATH}${NC}"
    exit 1
  fi

  cp "${LIB_PATH}" "${STEREO_TOOL_DIR}/st_plugin.so"

  # Clean up temporary files
  rm -rf "${TMP_DIR}" "${STEREO_TOOL_ZIP_PATH}"

  # Write StereoTool configuration
  STEREOTOOL_RC_PATH="${STEREO_TOOL_DIR}/.liquidsoap.rc"
  cat <<EOL > "${STEREOTOOL_RC_PATH}"
[Stereo Tool Configuration]
Enable web interface=1
Whitelist=/0
EOL
else
  # Remove StereoTool configuration from Liquidsoap script if not used
  sed -i '/# StereoTool implementation/,/output.dummy(radioproc)/d' "${LIQUIDSOAP_CONFIG_PATH}"
fi

# Determine the UID and GID of the liquidsoap user in the container
echo -e "${BLUE}►► Determining UID and GID of the liquidsoap user in the container...${NC}"
CONTAINER_IMAGE="savonet/liquidsoap:v${LIQUIDSOAP_VERSION}"
USER_INFO=$(docker run --rm --entrypoint /bin/sh "${CONTAINER_IMAGE}" -c 'id liquidsoap')

# Rename variables to avoid conflicts with shell built-in variables
LIQUIDSOAP_UID=$(echo "${USER_INFO}" | grep -oP 'uid=\K[0-9]+')
LIQUIDSOAP_GID=$(echo "${USER_INFO}" | grep -oP 'gid=\K[0-9]+')

if [ -z "${LIQUIDSOAP_UID}" ] || [ -z "${LIQUIDSOAP_GID}" ]; then
  echo -e "${RED}Error: Failed to retrieve UID or GID for the liquidsoap user.${NC}"
  exit 1
fi

echo "Liquidsoap UID: ${LIQUIDSOAP_UID}, GID: ${LIQUIDSOAP_GID}"

# Set ownership of directories
echo -e "${BLUE}►► Setting ownership for /opt/liquidsoap...${NC}"
chown -R "${LIQUIDSOAP_UID}:${LIQUIDSOAP_GID}" /opt/liquidsoap

echo -e "${GREEN}Installation completed successfully!${NC}"

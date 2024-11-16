#!/usr/bin/env bash

# Load functions library
FUNCTIONS_LIB_PATH="/tmp/functions.sh"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Liquidsoap configuration
LIQUIDSOAP_VERSION="2.3.0-rc2"  # TODO: On 2.3.0 check preset saving again!
LIQUIDSOAP_CONFIG_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/radio.liq"
AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"

# StereoTool configuration
STEREOTOOL_VERSION="1021"
STEREOTOOL_BASE_URL="https://download.thimeo.com"

# General configuration
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=("/opt/liquidsoap/scripts" "/opt/liquidsoap/audio")
OS_ARCH=$(dpkg --print-architecture)

# Download the latest version of the functions library
rm -f "${FUNCTIONS_LIB_PATH}"
if ! curl -sLo "${FUNCTIONS_LIB_PATH}" "${FUNCTIONS_LIB_URL}"; then
  echo -e "*** Failed to download functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
# shellcheck source=/tmp/functions.sh
source "${FUNCTIONS_LIB_PATH}"

# Environment setup
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone "${TIMEZONE}"

# Check if docker is installed 
require_tool "docker"

# Clear the terminal and display the banner
clear
cat << "EOF"
 ______     _     ___          __       _     ______ __  __ 
|___  /    (_)   | \ \        / /      | |   |  ____|  \/  |
   / /_   _ _  __| |\ \  /\  / /__  ___| |_  | |__  | \  / |
  / /| | | | |/ _` | \ \/  \/ / _ \/ __| __| |  __| | |\/| |
 / /_| |_| | | (_| |  \  /\  /  __/\__ \ |_  | |    | |  | |
/_____\__,_|_|\__,_|   \/  \/ \___||___/\__| |_|    |_|  |_|
EOF

# Greeting and user input
echo -e "${GREEN}⎎ Liquidsoap and StereoTool setup${NC}\n"
ask_user "USE_ST" "n" "Do you want to use StereoTool for sound processing? (y/n)" "y/n"
ask_user "DO_UPDATES" "y" "Do you want to perform all OS updates? (y/n)" "y/n"

# Perform OS updates if requested
if [ "${DO_UPDATES}" == "y" ]; then
  update_os silent
fi

# Create necessary directories
echo -e "${BLUE}►► Creating directories...${NC}"
for dir in "${DIRECTORIES[@]}"; do
  mkdir -p "${dir}"
done

# Backup existing configuration and download new configuration files
backup_file "/opt/liquidsoap/scripts/radio.liq"
echo -e "${BLUE}►► Downloading configuration files...${NC}"
curl -sLo "/opt/liquidsoap/audio/fallback.ogg" "${AUDIO_FALLBACK_URL}"
curl -sLo "/opt/liquidsoap/scripts/radio.liq" "${LIQUIDSOAP_CONFIG_URL}"

if [ "${USE_ST}" == "y" ]; then
  install_packages silent unzip
  echo -e "${BLUE}►► Installing StereoTool...${NC}"
  mkdir -p /opt/liquidsoap/stereotool

  # Download and extract StereoTool
  curl -sLo "/tmp/st.zip" "${STEREOTOOL_BASE_URL}/Stereo_Tool_Generic_plugin_${STEREOTOOL_VERSION}.zip"
  stereotool_tmp_dir=$(mktemp -d)
  unzip -o "/tmp/st.zip" -d "${stereotool_tmp_dir}"

  # Find the extracted versioned directory
  stereotool_extracted_dir=$(find "${stereotool_tmp_dir}" -maxdepth 1 -type d -name "libStereoTool_*" | head -n 1)

  # Check if the directory was found
  if [ ! -d "${stereotool_extracted_dir}" ]; then
    echo "Error: Could not find the extracted StereoTool directory."
    exit 1
  fi

  # Copy the appropriate library based on architecture
  case "${OS_ARCH}" in
    amd64)
      stereotool_lib_path="${stereotool_extracted_dir}/lib/Linux/IntelAMD/64/libStereoTool_intel64.so"
      ;;
    arm64)
      stereotool_lib_path="${stereotool_extracted_dir}/lib/Linux/ARM/64/libStereoTool_arm64.so"
      ;;
    *)
      echo "Unsupported architecture: ${OS_ARCH}"
      exit 1
      ;;
  esac

  # Check if the library file exists
  if [ ! -f "${stereotool_lib_path}" ]; then
    echo "Error: StereoTool library not found at ${stereotool_lib_path}"
    exit 1
  fi

  cp "${stereotool_lib_path}" "/opt/liquidsoap/stereotool/st_plugin.so"

  # Clean up temporary files
  rm -rf "${stereotool_tmp_dir}" "/tmp/st.zip"
else
  # Remove StereoTool configuration from Liquidsoap script if not used
  sed -i '/# StereoTool implementation/,/output.dummy(radioproc)/d' "/opt/liquidsoap/radio.liq"
fi

# Write minimal StereoTool configuration
cat <<EOL > /opt/liquidsoap/.liquidsoap.rc
[Stereo Tool Configuration]
Enable web interface=1
Whitelist=/0
EOL

echo -e "${GREEN}Setup completed successfully!${NC}"

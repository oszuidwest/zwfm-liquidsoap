#!/usr/bin/env bash

# Load functions library
FUNCTIONS_LIB_PATH="/tmp/functions.sh"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Liquidsoap configuration
LIQUIDSOAP_VERSION="2.2.5"  # TODO: On 2.3.0 check preset saving again!
LIQUIDSOAP_PACKAGE_BASE_URL="https://github.com/savonet/liquidsoap/releases/download/v${LIQUIDSOAP_VERSION}"
LIQUIDSOAP_CONFIG_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/radio.liq"
LIQUIDSOAP_SERVICE_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/liquidsoap.service"
AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"

# StereoTool configuration
STEREOTOOL_VERSION="1041"
STEREOTOOL_BASE_URL="https://download.thimeo.com"

# General settings
SUPPORTED_OS=("bookworm" "jammy")
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=("/etc/liquidsoap" "/var/audio")

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

# Detect and validate the operating system
os_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
os_version=$(lsb_release -cs)
os_arch=$(dpkg --print-architecture)

if [[ ! " ${SUPPORTED_OS[*]} " =~ (^|[[:space:]])${os_version}($|[[:space:]]) ]]; then
  printf "This script does not support '%s' OS version. Exiting.\n" "${os_version}"
  exit 1
fi

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

# Configure repositories on Debian Bookworm
if [ "${os_version}" == "bookworm" ]; then
  install_packages silent software-properties-common

  # Identify deb822 format source files
  deb822_files=()
  readarray -d '' deb822_files < <(find /etc/apt/sources.list.d/ -type f -name "*.sources" -print0)

  if [ "${#deb822_files[@]}" -gt 0 ]; then
    echo -e "${BLUE}►► Adding 'contrib' and 'non-free' components to the sources list (deb822 format)...${NC}"
    for source_file in "${deb822_files[@]}"; do
      # Modify Debian repository sources to include 'contrib', 'non-free', and 'non-free-firmware'
      if grep -qE '^Types:.*deb' "${source_file}" && \
         grep -qE "^Suites:.*${os_version}" "${source_file}" && \
         grep -qE '^Components:.*main' "${source_file}"; then
        backup_file "${source_file}"
        sed -i '/^Components:/ {
          /contrib/! s/$/ contrib/;
          /non-free/! s/$/ non-free/;
          /non-free-firmware/! s/$/ non-free-firmware/;
        }' "${source_file}"
      fi
    done
  else
    echo -e "${BLUE}►► Adding 'non-free' component using apt-add-repository...${NC}"
    apt-add-repository -y contrib non-free non-free-firmware
  fi
  apt update
fi

# Perform OS updates if requested
if [ "${DO_UPDATES}" == "y" ]; then
  update_os silent
fi

# Install Liquidsoap dependencies
install_packages silent fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink

# Install Liquidsoap
echo -e "${BLUE}►► Installing Liquidsoap...${NC}"
LIQUIDSOAP_PACKAGE_URL="${LIQUIDSOAP_PACKAGE_BASE_URL}/liquidsoap_${LIQUIDSOAP_VERSION}-${os_id}-${os_version}-1_${os_arch}.deb"
LIQUIDSOAP_PACKAGE_PATH="/tmp/liquidsoap_${LIQUIDSOAP_VERSION}.deb"
curl -sLo "${LIQUIDSOAP_PACKAGE_PATH}" "${LIQUIDSOAP_PACKAGE_URL}"
apt -qq -y install "${LIQUIDSOAP_PACKAGE_PATH}" --fix-broken

# Verify Liquidsoap installation
if ! command -v liquidsoap >/dev/null 2>&1; then
  echo -e "${RED}*** Error: Liquidsoap installation failed. Exiting. ***${NC}"
  exit 1
fi

# Create necessary directories
echo -e "${BLUE}►► Creating directories...${NC}"
for dir in "${DIRECTORIES[@]}"; do
  mkdir -p "${dir}"
  chown liquidsoap:liquidsoap "${dir}"
  chmod g+s "${dir}"
done

# Backup existing configuration and download new configuration files
backup_file "/etc/liquidsoap/radio.liq"
echo -e "${BLUE}►► Downloading configuration files...${NC}"
curl -sLo "/var/audio/fallback.ogg" "${AUDIO_FALLBACK_URL}"
curl -sLo "/etc/liquidsoap/radio.liq" "${LIQUIDSOAP_CONFIG_URL}"

if [ "${USE_ST}" == "y" ]; then
  install_packages silent unzip
  echo -e "${BLUE}►► Installing StereoTool...${NC}"
  mkdir -p /opt/stereotool

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
  case "${os_arch}" in
    amd64)
      stereotool_lib_path="${stereotool_extracted_dir}/lib/Linux/IntelAMD/64/libStereoTool_intel64.so"
      ;;
    arm64)
      stereotool_lib_path="${stereotool_extracted_dir}/lib/Linux/ARM/64/libStereoTool_arm64.so"
      ;;
    *)
      echo "Unsupported architecture: ${os_arch}"
      exit 1
      ;;
  esac

  # Check if the library file exists
  if [ ! -f "${stereotool_lib_path}" ]; then
    echo "Error: StereoTool library not found at ${stereotool_lib_path}"
    exit 1
  fi

  cp "${stereotool_lib_path}" "/opt/stereotool/st_plugin.so"

  # Clean up temporary files
  rm -rf "${stereotool_tmp_dir}" "/tmp/st.zip"
else
  # Remove StereoTool configuration from Liquidsoap script if not used
  sed -i '/# StereoTool implementation/,/output.dummy(radioproc)/d' "/etc/liquidsoap/radio.liq"
fi

# Write minimal StereoTool configuration
cat <<EOL > /usr/share/liquidsoap/.liquidsoap.rc
[Stereo Tool Configuration]
Enable web interface=1
Whitelist=/0
EOL

# Hotfix for preset saving issue (https://github.com/savonet/liquidsoap/issues/4161)
chmod 777 /usr/share/liquidsoap/
chown liquidsoap:liquidsoap /usr/share/liquidsoap/.liquidsoap.rc

# Set up Liquidsoap as a system service
echo -e "${BLUE}►► Setting up Liquidsoap service...${NC}"
rm -f "/etc/systemd/system/liquidsoap.service"
curl -sLo "/etc/systemd/system/liquidsoap.service" "${LIQUIDSOAP_SERVICE_URL}"
systemctl daemon-reload
systemctl enable liquidsoap.service

echo -e "${GREEN}Setup completed successfully!${NC}"

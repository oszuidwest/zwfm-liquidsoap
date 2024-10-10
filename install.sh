#!/usr/bin/env bash

# Load functions library
FUNCTIONS_LIB_PATH="/tmp/functions.sh"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Liquidsoap configuration
LIQUIDSOAP_VERSION="2.2.5"
LIQUIDSOAP_PACKAGE_BASE_URL="https://github.com/savonet/liquidsoap/releases/download/v$LIQUIDSOAP_VERSION"
LIQUIDSOAP_CONFIG_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/radio.liq"
LIQUIDSOAP_SERVICE_URL="https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/liquidsoap.service"
AUDIO_FALLBACK_URL="https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg"

# StereoTool configuration
STEREOTOOL_VERSION="1041"
STEREOTOOL_BASE_URL="https://download.thimeo.com"

# General settings
SUPPORTED_OS=("bookworm" "jammy")
TIMEZONE="Europe/Amsterdam"
DIRECTORIES=("/etc/liquidsoap" "/var/audio" "/usr/share/liquidsoap/.liquidsoap.presets/") 
#   Remove liquidsoap.presets after bug is resolved. 
#   It's a hotfix for https://github.com/savonet/liquidsoap/issues/4161 (saving presets fails)

# Download the latest version of the functions library
rm -f "$FUNCTIONS_LIB_PATH"
if ! curl -sLo "$FUNCTIONS_LIB_PATH" "$FUNCTIONS_LIB_URL"; then
  echo -e "*** Failed to download functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
# shellcheck source=/tmp/functions.sh
source "$FUNCTIONS_LIB_PATH"

# Environment setup
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone "$TIMEZONE"

# Detect and validate the operating system
os_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
os_version=$(lsb_release -cs)
os_arch=$(dpkg --print-architecture)

if [[ ! " ${SUPPORTED_OS[*]} " =~ ${os_version} ]]; then
  printf "This script does not support '%s' OS version. Exiting.\n" "$os_version"
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
if [ "$os_version" == "bookworm" ]; then
  install_packages silent software-properties-common

  # Identify deb822 format source files
  deb822_files=()
  readarray -d '' deb822_files < <(find /etc/apt/sources.list.d/ -type f -name "*.sources" -print0)

  if [ "${#deb822_files[@]}" -gt 0 ]; then
    echo -e "${BLUE}►► Adding 'contrib' and 'non-free' components to the sources list (deb822 format)...${NC}"
    for source_file in "${deb822_files[@]}"; do
      # Remove trailing null character from filename
      source_file="${source_file%$'\0'}"

      # Modify Debian repository sources to include 'contrib', 'non-free', and 'non-free-firmware'
      if grep -qE '^Types:.*deb' "$source_file" && \
         grep -qE "^Suites:.*$os_version" "$source_file" && \
         grep -qE '^Components:.*main' "$source_file"; then
        backup_file "$source_file"
        sed -i '/^Components:/ {
          /contrib/! s/$/ contrib/;
          /non-free/! s/$/ non-free/;
          /non-free-firmware/! s/$/ non-free-firmware/;
        }' "$source_file"
      fi
    done
  else
    echo -e "${BLUE}►► Adding 'non-free' component using apt-add-repository...${NC}"
    apt-add-repository -y contrib non-free non-free-firmware
  fi
  apt update
fi

# Perform OS updates if requested
if [ "$DO_UPDATES" == "y" ]; then
  update_os silent
fi

# Install Liquidsoap dependencies
install_packages silent fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink

# Install Liquidsoap
echo -e "${BLUE}►► Installing Liquidsoap...${NC}"
package_url="${LIQUIDSOAP_PACKAGE_BASE_URL}/liquidsoap_${LIQUIDSOAP_VERSION}-${os_id}-${os_version}-1_${os_arch}.deb"
liquidsoap_package="/tmp/liquidsoap_${LIQUIDSOAP_VERSION}.deb"
curl -sLo "$liquidsoap_package" "$package_url"
apt -qq -y install "$liquidsoap_package" --fix-broken

# Verify Liquidsoap installation
if ! command -v liquidsoap >/dev/null 2>&1; then
  echo -e "${RED}*** Error: Liquidsoap installation failed. Exiting. ***${NC}"
  exit 1
fi

# Create necessary directories
echo -e "${BLUE}►► Creating directories...${NC}"
for dir in "${DIRECTORIES[@]}"; do
  mkdir -p "$dir"
  chown liquidsoap:liquidsoap "$dir"
  chmod g+s "$dir"
done

# Backup existing configuration and download new configuration files
backup_file "/etc/liquidsoap/radio.liq"
echo -e "${BLUE}►► Downloading configuration files...${NC}"
curl -sLo /var/audio/fallback.ogg "$AUDIO_FALLBACK_URL"
curl -sLo /etc/liquidsoap/radio.liq "$LIQUIDSOAP_CONFIG_URL"

# Install and configure StereoTool if selected
if [ "$USE_ST" == "y" ]; then
  install_packages silent unzip
  echo -e "${BLUE}►► Installing StereoTool...${NC}"
  mkdir -p /opt/stereotool
  curl -sLo /tmp/st.zip "${STEREOTOOL_BASE_URL}/Stereo_Tool_Generic_plugin_${STEREOTOOL_VERSION}.zip"
  unzip -o /tmp/st.zip -d /tmp/
  extracted_dir=$(find /tmp/* -maxdepth 0 -type d -print0 | xargs -0 ls -td | head -n 1)

  if [ "$os_arch" == "amd64" ]; then
    cp "${extracted_dir}/lib/Linux/IntelAMD/64/libStereoTool_intel64.so" /opt/stereotool/st_plugin.so
    curl -sLo /opt/stereotool/st_standalone "${STEREOTOOL_BASE_URL}/stereo_tool_cmd_64_${STEREOTOOL_VERSION}"
  elif [ "$os_arch" == "arm64" ]; then
    cp "${extracted_dir}/lib/Linux/ARM/64/libStereoTool_arm64.so" /opt/stereotool/st_plugin.so
    curl -sLo /opt/stereotool/st_standalone "${STEREOTOOL_BASE_URL}/stereo_tool_pi2_64_${STEREOTOOL_VERSION}"
  fi
  chmod +x /opt/stereotool/st_standalone

  # Backup, generate and patch StereoTool settings file
  backup_file "/etc/liquidsoap/st.ini"
  /opt/stereotool/st_standalone -X /etc/liquidsoap/st.ini
  sed -i 's/^\(Whitelist=\).*$/\1\/0/' /etc/liquidsoap/st.ini
  sed -i 's/^\(Enable web interface=\).*$/\11/' /etc/liquidsoap/st.ini
else
  # Remove StereoTool configuration from Liquidsoap script if not used
  sed -i '/# StereoTool implementation/,/output.dummy(radioproc)/d' /etc/liquidsoap/radio.liq
fi

# Set up Liquidsoap as a system service
echo -e "${BLUE}►► Setting up Liquidsoap service...${NC}"
rm -f /etc/systemd/system/liquidsoap.service
curl -sLo /etc/systemd/system/liquidsoap.service "$LIQUIDSOAP_SERVICE_URL"
systemctl daemon-reload
systemctl enable liquidsoap.service

echo -e "${GREEN}Setup completed successfully!${NC}"

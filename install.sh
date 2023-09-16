#!/usr/bin/env bash

# Start with a clean terminal
clear

# Download the functions library
if ! curl -s -o /tmp/functions.sh https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh; then
  echo -e  "*** Failed to download functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions file
source /tmp/functions.sh

# Set color variables
set_colors

# Check if we are root
are_we_root

# Check if this is Linux
is_this_linux
is_this_os_64bit

# Detect OS version and architecture
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_VERSION=$(lsb_release -cs)
OS_ARCH=$(dpkg --print-architecture)

# Check if the OS version is supported
SUPPORTED_OS=("bullseye" "bookworm" "focal" "jammy")
OS_SUPPORTED=false

for os in "${SUPPORTED_OS[@]}"; do
  if [ "$OS_VERSION" == "$os" ]; then
    OS_SUPPORTED=true
    break
  fi
done

if [ "$OS_SUPPORTED" = false ]; then
  printf "This script does not support '%s' OS version. Exiting.\n" "$OS_VERSION"
  exit 1
fi

# Set the liquidsoap package download URL based on OS version and architecture
BASE_URL="https://github.com/savonet/liquidsoap/releases/download/v2.2.1/liquidsoap_2.2.1"
PACKAGE_URL="${BASE_URL}-${OS_ID}-${OS_VERSION}-1_${OS_ARCH}.deb"

# Ask for input for variables
ask_user "DO_UPDATES" "y" "Do you want to perform all OS updates? (y/n)" "y/n"
ask_user "USE_ST" "n" "Do you want to use StereoTool for sound processing? (y/n)" "y/n"

# Check if the DO_UPDATES variable is set to 'y'
if [ "$DO_UPDATES" == "y" ]; then
  update_os silent
fi

# Install FDKAAC and bindings
install_packages silent fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink

# Get deb package
wget "$PACKAGE_URL" -O /tmp/liq_2.2.1.deb

# Install deb package 
apt -qq -y install /tmp/liq_2.2.1.deb --fix-broken

# Make dirs for files
mkdir /etc/liquidsoap
mkdir /var/audio
chown -R liquidsoap:liquidsoap /etc/liquidsoap /var/audio

# Download StereoTool plug-in
if [ "$USE_ST" == "y" ]; then
  apt -qq -y install unzip
  mkdir -p /opt/stereotool
  wget https://download.thimeo.com/Stereo_Tool_Generic_plugin.zip -O /tmp/st.zip
  unzip -o /tmp/st.zip -d /tmp/
  
  # Detect the most recently created directory under /tmp/
  EXTRACTED_DIR=$(find /tmp/* -maxdepth 0 -type d -print0 | xargs -0 ls -td | head -n 1)

  # Check the system architecture and copy the correct plugin
  if [ "$OS_ARCH" == "amd64" ]; then
    cp "${EXTRACTED_DIR}libStereoTool_intel64.so" /opt/stereotool/plugin.so
  elif [ "$OS_ARCH" == "i386" ]; then
    cp "${EXTRACTED_DIR}libStereoTool_intel32.so" /opt/stereotool/plugin.so
  elif [ "$OS_ARCH" == "arm64" ]; then
    cp "${EXTRACTED_DIR}libStereoTool_arm64.so" /opt/stereotool/plugin.so
  elif [ "$OS_ARCH" == "armhf" ]; then
    cp "${EXTRACTED_DIR}libStereoTool_arm32.so" /opt/stereotool/plugin.so
  fi
fi


# Download StereoTool 
#if [ "$USE_ST" == "y" ]; then
#  mkdir -p /opt/stereotool
#  wget https://download.thimeo.com/stereo_tool_cmd_64 -O /opt/stereotool/stereotool
#  chmod +x /opt/stereotool/stereotool
#fi

# Download sample fallback file
wget https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg -O /var/audio/fallback.ogg

# Download radio.liq or radio-experimental.liq based on user input
if [ "$USE_ST" == "y" ]; then
  wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/radio-experimental.liq -O /etc/liquidsoap/radio.liq
else
  wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/radio.liq -O /etc/liquidsoap/radio.liq
fi

# Install service
rm -f /etc/systemd/system/liquidsoap.service
wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/liquidsoap.service -O /etc/systemd/system/liquidsoap.service
systemctl daemon-reload
systemctl enable liquidsoap.service

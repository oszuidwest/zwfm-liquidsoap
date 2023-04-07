#!/bin/bash

# Start with a clean terminal
clear

if [ "$(id -u)" != "0" ]; then
  printf "You must be root to execute the script. Exiting.\n"
  exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
  printf "This script does not support '%s' Operating System. Exiting.\n" "$(uname -s)"
  exit 1
fi

# Detect OS version and architecture
OS_VERSION=$(lsb_release -cs)
OS_ARCH=$(dpkg --print-architecture)

# Check if the OS version is supported
SUPPORTED_OS=("bookworm" "bullseye" "focal" "jammy")
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
BASE_URL="https://github.com/savonet/liquidsoap/releases/download/rolling-release-v2.2.x/liquidsoap-471bd7c_2.2.0"
PACKAGE_URL="${BASE_URL}-${OS_VERSION}-${OS_ARCH}.deb"

# Ask for input for variables
read -rp "Do you want to perform all OS updates? (default: y): " -i "y" DO_UPDATES

# Check if the DO_UPDATES variable is set to 'y'
if [ "$DO_UPDATES" == "y" ]; then
  apt -qq -y update >/dev/null 2>&1
  apt -qq -y upgrade >/dev/null 2>&1
  apt -qq -y autoremove >/dev/null 2>&1
fi

# Install FDKAAC and bindings
apt -qq -y install fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink >/dev/null 2>&1

# Install Unzip
apt -qq -y install unzip >/dev/null 2>&1

# Download Thimeo-ST plugin 
wget https://download.thimeo.com/Stereo_Tool_Generic_plugin.zip -O /tmp/st.zip

# Unzip Thimeo-ST plugin
unzip /tmp/st.zip -d /opt

# Get deb package
wget "$PACKAGE_URL" -O /tmp/liq_2.2.0.deb

# Install deb package 
apt -qq -y install /tmp/liq_2.2.0.deb --fix-broken

# Make dirs for files
mkdir /etc/liquidsoap
mkdir /var/audio
chown -R liquidsoap:liquidsoap /etc/liquidsoap /var/audio

# Download sample fallback file
wget https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg -O /var/audio/fallback.ogg

# Download radio.liq
wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/radio.liq -O /etc/liquidsoap/radio.liq

# Install service
wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/liquidsoap.service -O /etc/systemd/system/liquidsoap.service
systemctl daemon-reload
systemctl enable liquidsoap.service

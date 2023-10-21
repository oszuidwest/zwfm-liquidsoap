#!/usr/bin/env bash

# Initialize the environment
clear
if ! curl -s -o /tmp/functions.sh https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh; then
    echo "*** Failed to download functions library. Please check your network connection! ***"
    exit 1
fi
source /tmp/functions.sh
set_colors

# Configure environment
are_we_root
is_this_linux
is_this_os_64bit
set_timezone Europe/Amsterdam

# Detect OS details
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_VERSION=$(lsb_release -cs)
OS_ARCH=$(dpkg --print-architecture)

# Validate OS version
SUPPORTED_OS=("bookworm" "jammy")
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

# OS-specific configurations
if [ "$OS_VERSION" == "bookworm" ]; then
    cp /etc/apt/sources.list "/etc/apt/sources.list.backup.$(date +%F)"
    sed -i '/^deb\|^deb-src/ { / non-free \| non-free$/!s/$/ non-free/ }' /etc/apt/sources.list
fi

# Set package URLs
BASE_URL="https://github.com/savonet/liquidsoap/releases/download/v2.2.1/liquidsoap_2.2.1"
PACKAGE_URL="${BASE_URL}-${OS_ID}-${OS_VERSION}-1_${OS_ARCH}.deb"

# User input for script execution
ask_user "DO_UPDATES" "y" "Do you want to perform all OS updates? (y/n)" "y/n"
ask_user "USE_ST" "n" "Do you want to use StereoTool for sound processing? (y/n)" "y/n"

# Perform OS updates if desired by user
if [ "$DO_UPDATES" == "y" ]; then
    update_os silent
fi

# Install necessary packages
install_packages silent fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink
wget "$PACKAGE_URL" -O /tmp/liq_2.2.1.deb
apt -qq -y install /tmp/liq_2.2.1.deb --fix-broken

# Configure directories
mkdir /etc/liquidsoap
mkdir /var/audio
chown -R liquidsoap:liquidsoap /etc/liquidsoap /var/audio

# Download and install StereoTool if desired by user
if [ "$USE_ST" == "y" ]; then
    install_packages silent unzip
    mkdir -p /opt/stereotool
    wget https://download.thimeo.com/Stereo_Tool_Generic_plugin.zip -O /tmp/st.zip
    unzip -o /tmp/st.zip -d /tmp/
    EXTRACTED_DIR=$(find /tmp/* -maxdepth 0 -type d -print0 | xargs -0 ls -td | head -n 1)
    
    if [ "$OS_ARCH" == "amd64" ]; then
        cp "${EXTRACTED_DIR}/libStereoToolX11_intel64.so" /opt/stereotool/st_plugin.so
        wget https://download.thimeo.com/stereo_tool_cmd_64_1011 -O /opt/stereotool/st_standalone
    elif [ "$OS_ARCH" == "arm64" ]; then
        cp "${EXTRACTED_DIR}/libStereoTool_arm64.so" /opt/stereotool/st_plugin.so
        wget https://download.thimeo.com/stereo_tool_pi2_64_1011 -O /opt/stereotool/st_standalone
    fi
    chmod +x /opt/stereotool/st_standalone
fi

# Fetch fallback sample and configuration files
wget https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg -O /var/audio/fallback.ogg
wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/main/radio.liq -O /etc/liquidsoap/radio.liq

# Install and set up service
rm -f /etc/systemd/system/liquidsoap.service
wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/main/liquidsoap.service -O /lib/systemd/system/liquidsoap.service
systemctl daemon-reload
if ! systemctl is-enabled liquidsoap.service; then
    systemctl enable liquidsoap.service
fi

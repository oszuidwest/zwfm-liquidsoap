#!/bin/bash

# Start with a clean terminal
clear

if [ "$(id -u)" != "0" ]; then
	printf "You must be root to execute the script. Exiting."
	exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
	printf "This script does not support '%s' Operating System. Exiting.\n" "$(uname -s)"
	exit 1
fi

if [ "$(cat /etc/debian_version)" != "bookworm/sid" ]; then
	printf "This script only supports Ubuntu 22.04 LTS. Exiting."
	exit 1
fi

# Update OS
apt -qq -y update >/dev/null 2>&1
apt -qq -y upgrade >/dev/null 2>&1
apt -qq -y autoremove >/dev/null 2>&1

# Install FDKAAC and bindings
apt -qq --yes install fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink >/dev/null 2>&1

# Get deb package
wget https://github.com/savonet/liquidsoap/releases/download/rolling-release-v2.2.x/liquidsoap-a7eea64_2.2.0-ubuntu-jammy-1_amd64.deb -O /tmp/liq_2.2.0_amd64.deb

# Install deb package 
apt -qq -y install /tmp/liq_2.2.0_amd64.deb --fix-broken

# Make dirs for files
sudo mkdir /etc/liquidsoap
sudo mkdir /var/audio
sudo chown -R liquidsoap:liquidsoap /etc/liquidsoap /var/audio

# Download sample fallback file
sudo wget https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg -O /var/audio/fallback.ogg

# Download radio.liq
sudo wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/radio.liq -O /etc/liquidsoap/radio.liq

# Install service
sudo wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/srt/liquidsoap.service -O /etc/systemd/system/liquidsoap.service
sudo systemctl daemon-reload
sudo systemctl enable liquidsoap.service

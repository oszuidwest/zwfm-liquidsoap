#!/bin/sh

set -e

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
sudo apt --quiet --quiet --yes update
sudo apt --quiet --quiet --yes upgrade
sudo apt --quiet --quiet --yes dist-upgrade
sudo apt --quiet --quiet --yes autoremove

# Install FDKAAC and bindings
sudo apt install fdkaac libfdkaac-ocaml libfdkaac-ocaml-dynlink -y

# Get deb package
wget https://github.com/savonet/liquidsoap/releases/download/v2.1.3/liquidsoap_2.1.3-ubuntu-jammy-1_amd64.deb -O /tmp/liq_2.1.3_amd64.deb

# Install deb package 
sudo apt install /tmp/liq_2.1.3_amd64.deb --fix-broken --yes

# Make dirs for files
sudo mkdir /etc/liquidsoap
sudo mkdir /var/audio
sudo chown -R liquidsoap:liquidsoap /etc/liquidsoap /var/audio

# Download sample fallback file
sudo wget https://upload.wikimedia.org/wikipedia/commons/6/66/Aaron_Dunn_-_Sonata_No_1_-_Movement_2.ogg -O /var/audio/fallback.ogg

# Download radio.liq
sudo wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/main/radio.liq -O /etc/liquidsoap/radio.liq

# Install service
sudo wget https://raw.githubusercontent.com/oszuidwest/liquidsoap-ubuntu/main/liquidsoap.service -O /etc/systemd/system/liquidsoap.service
sudo systemctl daemon-reload
sudo systemctl enable liquidsoap.service

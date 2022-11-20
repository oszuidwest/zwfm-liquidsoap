#!/bin/sh

set -e

if [ "$(id -u)" != "0" ]; then
	printf "You must be root to execute the script. Exiting."
	exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
	printf "This script does not support \"$(uname -s)\" Operating System. Exiting."
	exit 1
fi

if [ "$(cat /etc/debian_version)" != "bookworm/sid" ]; then
	printf "This script is only tested on Ubuntu 22.04 LTS. Exiting."
	exit 1
fi

# Download stereotool
sudo wget https://www.stereotool.com/download/stereo_tool_cmd_64 -O /usr/bin/stereotool

# Configure stereotool
sudo mkdir /etc/stereotool
sudo chmod +x /usr/bin/stereotool
sudo stereotool -X /etc/stereotool/st.ini

# Grant stereotool access to ports < 1024
sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/stereotool

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

# Check if this is Linux x64
is_this_linux
is_this_os_64bit

# Define the server private and public key paths
readonly PRIVATE_KEY_PATH="/etc/wireguard/privatekey"
readonly PUBLIC_KEY_PATH="/etc/wireguard/publickey"

# Check if WireGuard is installed, if not, install it
if ! command -v wg >/dev/null 2>&1; then
  echo "WireGuard is not installed. Installing it..."
  install_packages silent wireguard
fi

# Check if the server keys exist. If not, generate them
if [[ -f "$PRIVATE_KEY_PATH" ]] && [[ -f "$PUBLIC_KEY_PATH" ]]; then
    echo "Server keys already exist. No action required."
else
    echo "Server keys are missing. Generating new keys..."
    rm -f "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"
    umask 077
    wg genkey | tee "$PRIVATE_KEY_PATH" | wg pubkey > "$PUBLIC_KEY_PATH"
fi

# Read the generated private key
GENERATED_PRIVATE_KEY="$(cat $PRIVATE_KEY_PATH)"

# Configure the WireGuard interface
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 172.16.0.1/24
PrivateKey = ${GENERATED_PRIVATE_KEY}
ListenPort = 51820

# Client 1
#[Peer]
#PublicKey = your_client_public_key_1
#AllowedIPs = 172.16.0.2/32
# Add clients by uncommenting and duplicating this part
EOF

# Setup IP Forwarding
readonly SYSCTL_CONF="/etc/sysctl.d/99-sysctl.conf"
readonly IP_FORWARD="net.ipv4.ip_forward=1"

if ! grep -Fxq "$IP_FORWARD" $SYSCTL_CONF; then
    echo "IP Forwarding is not enabled. Updating configuration..."
    grep -Fxq "#$IP_FORWARD" $SYSCTL_CONF && sed -i "s/#\s*${IP_FORWARD}/${IP_FORWARD}/" $SYSCTL_CONF || echo "$IP_FORWARD" >> $SYSCTL_CONF
    sysctl -p $SYSCTL_CONF
fi

# Enable the WireGuard interface on boot
systemctl enable wg-quick@wg0

# Bring up the WireGuard interface
wg-quick up wg0

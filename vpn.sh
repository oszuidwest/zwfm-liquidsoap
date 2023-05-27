#!/bin/bash
set -e

# Define the server private and public key paths
readonly SERVER_PRIVATE_KEY="/etc/wireguard/server_private_key"
readonly SERVER_PUBLIC_KEY="/etc/wireguard/server_public_key"

# Ensure the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Check if WireGuard is installed, if not, install it
if ! command -v wg >/dev/null 2>&1; then
  echo "WireGuard is not installed. Updating system and installing WireGuard..."
  apt update -qq -y && apt install -qq -y wireguard
fi

# Check if the server keys exist. If not, generate them
if [[ -f "$SERVER_PRIVATE_KEY" ]] && [[ -f "$SERVER_PUBLIC_KEY" ]]; then
    echo "Server keys already exist. No action required."
else
    echo "Server keys are missing. Generating new keys..."
    rm -f "$SERVER_PRIVATE_KEY" "$SERVER_PUBLIC_KEY"
    umask 077
    wg genkey | tee "$SERVER_PRIVATE_KEY" | wg pubkey > "$SERVER_PUBLIC_KEY"
fi

# Read private key
PRIVATE_KEY="$(cat "$SERVER_PRIVATE_KEY")"

# Configure the WireGuard interface
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 172.16.0.1/24
PrivateKey = ${PRIVATE_KEY}
ListenPort = 51820

# Raspberry Pi client 1
[Peer]
PublicKey = your_client_public_key_1
AllowedIPs = 172.16.0.2/32
# Add more clients by duplicating this part
EOF

# Bring up the WireGuard interface
wg-quick up wg0

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

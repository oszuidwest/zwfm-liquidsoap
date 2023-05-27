#!/bin/bash

# Define the server private and public key paths
SERVER_PRIVATE_KEY="/etc/wireguard/server_private_key"
SERVER_PUBLIC_KEY="/etc/wireguard/server_public_key"

# Only run as root
if [ "$(id -u)" != "0" ]; then
  printf "You must be root to execute the script. Exiting.\n"
  exit 1
fi

# Ensure wg command is available
if ! command -v wg &> /dev/null; then
  echo "WireGuard does not seem to be installed. Updating system and installing WireGuard..."
  apt update -qq -y
  apt install -qq -y wireguard
fi

# Check if server private and public keys exist
if [[ -f "$SERVER_PRIVATE_KEY" ]] && [[ -f "$SERVER_PUBLIC_KEY" ]]; then
    echo "Server private and public keys already exist. Not making new ones"
else
    echo "Server private and/or public key missing. Generating new key pair..."
    rm -f "$SERVER_PRIVATE_KEY" "$SERVER_PUBLIC_KEY"
    umask 077
    wg genkey | tee "$SERVER_PRIVATE_KEY" | wg pubkey > "$SERVER_PUBLIC_KEY"
fi

# Configure the WireGuard interface
cat << EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 172.16.0.1/24
PrivateKey = ${SERVER_PRIVATE_KEY}
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
FILE="/etc/sysctl.d/99-sysctl.conf"
LINE="net.ipv4.ip_forward=1"

if ! grep -Fxq "$LINE" $FILE
then
    echo "IP Forwarding is not enabled, updating configuration..."
    grep -Fxq "#$LINE" $FILE && sed -i "s/#[[:space:]]*$LINE/$LINE/g" $FILE || echo "$LINE" >> $FILE
    sysctl -p $FILE
fi

# Enable the WireGuard interface on boot
systemctl enable wg-quick@wg0

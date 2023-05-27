#!/bin/bash

# Update the system
apt update && apt upgrade -y

# Install WireGuard
apt install -y wireguard

# Generate the server private and public keys
wg genkey | tee /etc/wireguard/server_private_key | wg pubkey > /etc/wireguard/server_public_key

# Retrieve the server private key
server_private_key=$(cat /etc/wireguard/server_private_key)

# Configure the WireGuard interface
cat << EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 172.16.0.1/24
PrivateKey = ${server_private_key}
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
    echo "Line is not in the file or commented out, updating..."
    grep -Fxq "#$LINE" $FILE && sed -i "s/#[[:space:]]*$LINE/$LINE/g" $FILE || echo "$LINE" >> $FILE
    sysctl -p $FILE
fi

# Enable the WireGuard interface on boot
systemctl enable wg-quick@wg0

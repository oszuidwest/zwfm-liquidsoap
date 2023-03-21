#!/bin/bash

# Start with a clean terminal
clear

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

clear
printf "********************************\n"
printf "ICECAST 2 INSTALLER\n"
printf "********************************\n"
read -rp "Specify the host name (for example: icecast.zuidwestfm.nl. Enter it without http:// or www) please: " HOSTNAME
read -rp "Specify the source and relay password: " SOURCEPASS
read -rp "Specify the admin password: " ADMINPASS
read -rp "Where is this server located (visible on admin pages)? " LOCATED
read -rp "What's the admins e-mail (visible on admin pages and for let's encrypt)? " ADMINMAIL
read -rp "Specify the port (default: 80): " PORT
read -rp "Do you want Let's Encrypt to get a certificate for this server? (y/n): " SSL

# Assume port is 80 if no port was entered
if [ -z "$PORT" ]; then
    PORT=80
    printf "You didn't specify a port. We assume port 80.\n"
fi

# If port is not 80 ssl is not possible
if [ "$PORT" != "80" ]; then
    SSL="n"
    printf "Since the specified port is not 80, SSL is not possible. Disabling SSL.\n"
fi

# Set vars
export DEBIAN_FRONTEND="noninteractive"

cat << EOF | sudo debconf-set-selections
icecast2 icecast2/hostname string $HOSTNAME
icecast2 icecast2/sourcepassword string $SOURCEPASS
icecast2 icecast2/relaypassword string $SOURCEPASS
icecast2 icecast2/adminpassword string $ADMINPASS
icecast2 icecast2/icecast-setup boolean true
EOF

# Update OS
apt -qq -y update >/dev/null 2>&1
apt -qq -y upgrade >/dev/null 2>&1
apt -qq -y autoremove >/dev/null 2>&1

# Remove old installs
apt -qq -y remove icecast2 certbot

# Install icecast2
apt -qq -y install icecast2 certbot

# Post configuration
sed -i 	-e "s|<location>[^<]*</location>|<location>$LOCATED</location>|" \
	-e "s|<admin>[^<]*</admin>|<admin>$ADMINMAIL</admin>|" \
	-e "s|<clients>[^<]*</clients>|<clients>250</clients>|" \
	-e "s|<sources>[^<]*</sources>|<sources>5</sources>|" \
	-e "0,/<port>/{s/<port>[0-9]\{1,5\}<\/port>/<port>$PORT<\/port>/;}" \
	/etc/icecast2/icecast.xml 2>/dev/null 1>&2

# Grant icecast access to ports < 1024
setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/icecast2

# Apply post configuration
systemctl enable icecast2
systemctl daemon-reload
service icecast2 restart

# If port is 80 and SSL is enabled, nudge the user to run certbot
if [ "$PORT" = "80" ] && [ "$SSL" = "y" ]; then
    echo "You should edit icecast.xml to reflect the new port situation and get a certificate with certbot. I can't do that yet..."
fi

### SSL IS WIP
## This currently doesn't work because let's encrypt _requires_ validation over port 80 while icecast is on port 8000.
# certbot --quiet --text --agree-tos --email $ADMINMAIL --noninteractive --no-eff-email --webroot --webroot-path="/usr/share/icecast2/web" -d "$HOSTNAME" --deploy-hook "cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /usr/share/icecast2/icecast.pem && service icecast2 reload" certonly --test-cert --dry-run
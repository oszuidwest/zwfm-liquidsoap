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

clear
printf "********************************\n"
printf "ICECAST 2 INSTALLER\n"
printf "********************************\n"
printf "> Specify the host name (for example: icecast.zuidwestfm.nl. Enter it without http:// or www) please: "
read -r HOSTNAME
printf "> Specify the source and relay password: "
read -r SOURCEPASS
printf "> Specify the admin password: "
read -r ADMINPASS
printf "> Where is this server located (visible on admin pages)? "
read -r LOCATED
printf "> What's the admins e-mail (visible on admin pages and for let's encrypt)? "
read -r ADMINMAIL
printf "> Do you want SSL (y/n)? "
read -r SSL
printf "> Specify the port (default: 80): "
read -r PORT

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
sudo apt --quiet --quiet --yes update
sudo apt --quiet --quiet --yes upgrade
sudo apt --quiet --quiet --yes dist-upgrade
sudo apt --quiet --quiet --yes autoremove

# Remove old installs
sudo apt --quiet --quiet --yes remove icecast2 certbot

# Install icecast2
sudo apt --quiet --quiet --yes install icecast2 certbot

# Post configuration
sed -i 	-e "s|<location>[^<]*</location>|<location>$LOCATED</location>|" \
	-e "s|<admin>[^<]*</admin>|<admin>$ADMINMAIL</admin>|" \
	-e "s|<clients>[^<]*</clients>|<clients>250</clients>|" \
	-e "s|<sources>[^<]*</sources>|<sources>5</sources>|" \
	/etc/icecast2/icecast.xml 2>/dev/null 1>&2

# Replace the first port element in the Icecast config file with the configured port
sed -i "0,/<port>/{s/<port>[0-9]\{1,5\}<\/port>/<port>$PORT<\/port>/;}" /etc/icecast2/icecast.xml

# Grant icecast access to ports < 1024
sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/icecast2

# Apply post configuration
systemctl enable icecast2
systemctl daemon-reload
service icecast2 restart

# If port is 80 and SSL is enabled, nudge the user to run certbot
if [ "$PORT" = "80" ] && [ "$SSL" = "y" ]; then
    echo "You should edit icecast.xml to reflect the new port situation and get a certificate with certbot. I can't do that yet..."
# If port is 80 and SSL is disabled, nudge the user to edit icecast.xml
elif [ "$PORT" = "80" ] && [ "$SSL" = "n" ]; then
    echo "You should edit icecast.xml to reflect the new port situation. I can't do that yet..."
# If port is not 80 and SSL is not enabled, show a message
else
    echo "Icecast was installed. Happy streaming"
fi

### SSL IS WIP
## This currently doesn't work because let's encrypt _requires_ validation over port 80 while icecast is on port 8000.
# certbot --quiet --text --agree-tos --email $ADMINMAIL --noninteractive --no-eff-email --webroot --webroot-path="/usr/share/icecast2/web" -d "$HOSTNAME" --deploy-hook "cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /usr/share/icecast2/icecast.pem && service icecast2 reload" certonly --test-cert --dry-run

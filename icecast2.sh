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

# Check if this is Linux
is_this_linux
is_this_os_64bit

clear
printf "********************************\n"
printf "ICECAST 2 INSTALLER\n"
printf "********************************\n"
ask_user "HOSTNAME" "localhost" "Specify the host name (for example: icecast.zuidwestfm.nl. Enter it without http:// or www) please" "str"
ask_user "SOURCEPASS" "hackme" "Specify the source and relay password" "str"
ask_user "ADMINPASS" "hackme" "Specify the admin password" "str"
ask_user "LOCATED" "Earth" "Where is this server located (visible on admin pages)?" "str"
ask_user "ADMINMAIL" "root@localhost" "What's the admins e-mail (visible on admin pages and for let's encrypt)?" "email"
ask_user "PORT" "80" "Specify the port" "num"
ask_user "SSL" "n" "Do you want Let's Encrypt to get a certificate for this server? (y/n)" "y/n"

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
update_os silent

# Install packages
install_packages silent icecast2 certbot

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
# certbot --quiet --text --agree-tos --email $ADMINMAIL --noninteractive --no-eff-email --webroot --webroot-path="/usr/share/icecast2/web" -d "$HOSTNAME" --deploy-hook "cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /usr/share/icecast2/icecast.pem && service icecast2 restart" certonly --test-cert --dry-run

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
	printf "This script only supports Ubuntu 22.04 LTS. Exiting."
	exit 1
fi

clear
printf "********************************\n"
printf "ICECAST 2 INSTALLER\n"
printf "********************************\n"
printf "> Specify the host name (without http:// or www) please: "
read HOSTNAME
printf "> Specify the source and relay password: "
read SOURCEPASS
printf "> Specify the admin password: "
read ADMINPASS
printf "> Where is this server located (visible on admin pages)? "
read LOCATED
printf "> What's the admins e-mail (visible on admin pages and for let's encrypt)? "
read ADMINMAIL
printf "> Do you want SSL (y/n)? "
read SSL
#Todo: ask user for port
#Todo: if port is not 80 ssl is not possible

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
sudo apt --quiet --quiet --yes remove icecast2

# Install icecast2
sudo apt --quiet --quiet --yes install icecast2

# Post configuration
sed -i 	-e "s|<location>[^<]*</location>|<location>$LOCATED</location>|" \
	-e "s|<admin>[^<]*</admin>|<admin>$ADMINMAIL</admin>|" \
	/etc/icecast2/icecast.xml 2>/dev/null 1>&2

# Grant icecast access to ports < 1024
sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/icecast2

# Apply post configuration
service icecast2 restart

### SSL IS WIP
## This currently doesn't work because let's encrypt _requires_ validation over port 80 while icecast is on port 8000.
certbot --quiet --text --agree-tos --email $ADMINMAIL --noninteractive --no-eff-email --webroot --webroot-path="/usr/share/icecast2/web" -d "$HOSTNAME" --deploy-hook "cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /etc/icecast2/bundle.pem && service icecast2 reload" certonly --test-cert --dry-run
cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /usr/share/icecast2/icecast.pem
chmod 666 /usr/share/icecast2/icecast.pem

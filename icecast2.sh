#!/bin/sh

set -e

if [ "$(id -u)" != "0" ]; then
	echo "You must be root to execute the script. Exiting."
	exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
	echo "This script does not support \"$(uname -s)\" Operating System. Exiting."
	exit 1
fi

if [ "$(cat /etc/debian_version)" != "bookworm/sid" ]; then
	echo "This script only supports Ubuntu 22.04 LTS. Exiting."
	exit 1
fi

echo "********************************"
echo "ICECAST 2 INSTALLER"
echo "********************************"
echo "> Specify the host name (without http:// or www) please"
read HOSTNAME
echo "> Specify the source and relay password"
read SOURCEPASS
echo "> Specify the admin password"
read ADMINPASS
echo "> Where is this server located (visible on admin pages)?"
read LOCATED
echo "> What's the admins e-mail (visible on admin pages and for let's encrypt)?"
read ADMINMAIL

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

# Apply post configuration
service icecast2 restart

### SSL IS WIP
certbot --quiet --text --agree-tos --email $ADMINMAIL --noninteractive --no-eff-email --webroot --webroot-path="/usr/share/icecast2/web" -d '$HOSTNAME' --deploy-hook "cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /etc/icecast2/bundle.pem && service icecast2 reload" certonly --test-cert --dry-run
cat /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/letsencrypt/live/$HOSTNAME/privkey.pem > /etc/icecast2/bundle.pem
chmod 666 /etc/icecast2/bundle.pem
#!/usr/bin/env bash

# Clear terminal
clear

# Download the functions library
if ! curl -s -o /tmp/functions.sh https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh; then
  echo -e "*** Failed to download functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
source /tmp/functions.sh

# Display a fancy banner for the sysadmin
cat << "EOF"
 ______     _     ___          __       _     ______ __  __ 
|___  /    (_)   | \ \        / /      | |   |  ____|  \/  |
   / /_   _ _  __| |\ \  /\  / /__  ___| |_  | |__  | \  / |
  / /| | | | |/ _` | \ \/  \/ / _ \/ __| __| |  __| | |\/| |
 / /_| |_| | | (_| |  \  /\  /  __/\__ \ |_  | |    | |  | |
/_____\__,_|_|\__,_|   \/  \/ \___||___/\__| |_|    |_|  |_|

               ********************************
                      ICECAST 2 INSTALLER
               ********************************

EOF

# Configure the environment
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone Europe/Amsterdam

# Collect user inputs
ask_user "HOSTNAMES" "localhost" "Specify the host name(s) (e.g., icecast.example.com) separated by a space (enter without http:// or www) please" "str"
ask_user "SOURCEPASS" "hackme" "Specify the source and relay password" "str"
ask_user "ADMINPASS" "hackme" "Specify the admin password" "str"
ask_user "LOCATED" "Earth" "Where is this server located (visible on admin pages)?" "str"
ask_user "ADMINMAIL" "root@localhost.local" "What's the admin's e-mail (visible on admin pages and for Let's Encrypt)?" "email"
ask_user "PORT" "80" "Specify the port" "num"
ask_user "SSL" "n" "Do you want Let's Encrypt to get a certificate for this server? (y/n)" "y/n"

# Sanitize the entered hostname(s)
HOSTNAMES=$(echo "$HOSTNAMES" | xargs)
IFS=' ' read -r -a HOSTNAMES_ARRAY <<< "$HOSTNAMES"
sanitized_domains=()
for domain in "${HOSTNAMES_ARRAY[@]}"; do
  sanitized_domain=$(echo "$domain" | tr -d '[:space:]')
  sanitized_domains+=("$sanitized_domain")
done

# Order the entered hostname(s)
HOSTNAMES_ARRAY=("${sanitized_domains[@]}")
PRIMARY_HOSTNAME="${HOSTNAMES_ARRAY[0]}"

# Build the domain flags for Certbot (e.g., -d domain1 -d domain2 ...)
DOMAINS_FLAGS=""
for domain in "${HOSTNAMES_ARRAY[@]}"; do
  DOMAINS_FLAGS="$DOMAINS_FLAGS -d $domain"
done

# Update the OS and install necessary packages
update_os silent
install_packages silent icecast2 certbot

# Generate the initial icecast.xml configuration
ICECAST_XML="/etc/icecast2/icecast.xml"
cat <<EOF > "$ICECAST_XML"
<icecast>
  <location>$LOCATED</location>
  <admin>$ADMINMAIL</admin>
  <hostname>$PRIMARY_HOSTNAME</hostname>

  <limits>
    <clients>5000</clients>
    <sources>25</sources>
    <burst-size>265536</burst-size>
  </limits>

  <authentication>
    <source-password>$SOURCEPASS</source-password>
    <relay-password>$SOURCEPASS</relay-password>
    <admin-user>admin</admin-user>
    <admin-password>$ADMINPASS</admin-password>
  </authentication>

  <listen-socket>
    <port>$PORT</port>
  </listen-socket>

  <http-headers>
    <header name="Access-Control-Allow-Origin" value="*" />
    <header name="X-Robots-Tag" value="noindex, noarchive" />
  </http-headers>

  <paths>
    <basedir>/usr/share/icecast2</basedir>
    <logdir>/var/log/icecast2</logdir>
    <webroot>/usr/share/icecast2/web</webroot>
    <adminroot>/usr/share/icecast2/admin</adminroot>
    <alias source="/" destination="/status.xsl"/>
  </paths>

  <logging>
    <logsize>10000</logsize>
  </logging>
</icecast>
EOF

# Set capabilities so that Icecast can listen on ports 80/443
setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/icecast2

# Reload and restart the Icecast service
systemctl enable icecast2
systemctl daemon-reload
systemctl restart icecast2

# SSL configuration
if [ "$SSL" = "y" ] && [ "$PORT" = "80" ]; then
  echo -e "${BLUE}►► Running Certbot to obtain SSL certificate for domains: ${HOSTNAMES_ARRAY[*]} ${NC}"
  certbot --text --agree-tos --email "$ADMINMAIL" --noninteractive --no-eff-email \
    --webroot --webroot-path="/usr/share/icecast2/web" "$DOMAINS_FLAGS" \
    --deploy-hook "cat /etc/letsencrypt/live/$PRIMARY_HOSTNAME/fullchain.pem /etc/letsencrypt/live/$PRIMARY_HOSTNAME/privkey.pem > /usr/share/icecast2/icecast.pem && systemctl restart icecast2" \
    certonly

  # Check if Certbot successfully obtained a certificate
  if [ -f "/usr/share/icecast2/icecast.pem" ]; then
    # Update icecast.xml with SSL settings
    sed -i "/<paths>/a \
    \    <ssl-certificate>/usr/share/icecast2/icecast.pem</ssl-certificate>" "$ICECAST_XML"
    
    sed -i "/<\/listen-socket>/a \
    <listen-socket>\n\
        <port>443</port>\n\
        <ssl>1</ssl>\n\
    </listen-socket>" "$ICECAST_XML"

    # Restart Icecast to apply the new configuration
    echo -e "${BLUE}►► Restarting Icecast with SSL support${NC}"
    systemctl restart icecast2
  else
    echo -e "${YELLOW} !! SSL certificate acquisition failed. Icecast will continue running on port ${PORT}.${NC}"
  fi
else
  if [ "$SSL" = "y" ]; then
    echo -e "${YELLOW} !! SSL setup is only possible when Icecast is running on port 80. You entered port ${PORT}. Skipping SSL configuration.${NC}"
  fi
fi

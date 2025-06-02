#!/usr/bin/env bash

# Load the functions library
FUNCTIONS_LIB_PATH="/tmp/functions.sh"
FUNCTIONS_LIB_URL="https://raw.githubusercontent.com/oszuidwest/bash-functions/main/common-functions.sh"

# Download the latest version of the functions library
rm -f "${FUNCTIONS_LIB_PATH}"
if ! curl -sLo "${FUNCTIONS_LIB_PATH}" "${FUNCTIONS_LIB_URL}"; then
  echo -e "*** Failed to download the functions library. Please check your network connection! ***"
  exit 1
fi

# Source the functions library
# shellcheck source=/tmp/functions.sh
source "${FUNCTIONS_LIB_PATH}"

# Define constants
ICECAST_CONFIG_DIR="/etc/icecast2"
ICECAST_XML="${ICECAST_CONFIG_DIR}/icecast.xml"
ICECAST_WEBROOT="/usr/share/icecast2/web"
ICECAST_PEM_PATH="/usr/share/icecast2/icecast.pem"
LETSENCRYPT_HOOKS_DIR="/etc/letsencrypt/renewal-hooks/deploy"
TIMEZONE="Europe/Amsterdam"

# Environment setup
set_colors
check_user_privileges privileged
is_this_linux
is_this_os_64bit
set_timezone "${TIMEZONE}"

# Display a welcome banner
clear
cat << "EOF"
 ______     _     ___          __       _     ______ __  __ 
|___  /    (_)   | \ \        / /      | |   |  ____|  \/  |
   / /_   _ _  __| |\ \  /\  / /__  ___| |_  | |__  | \  / |
  / /| | | | |/ _` | \ \/  \/ / _ \/ __| __| |  __| | |\/| |
 / /_| |_| | | (_| |  \  /\  /  __/\__ \ |_  | |    | |  | |
/_____\__,_|_|\__,_|   \/  \/ \___||___/\__| |_|    |_|  |_|

EOF
echo -e "${GREEN}⎎ Icecast 2 Installation and Configuration${NC}\n"

# Prompt user for input
ask_user "HOSTNAMES" "localhost" "Specify the host name(s) (e.g., icecast.example.com) separated by a space (enter without http:// or www) please" "str"
ask_user "SOURCEPASS" "hackme" "Specify the source and relay password" "str"
ask_user "ADMINPASS" "hackme" "Specify the admin password" "str"
ask_user "LOCATED" "Earth" "Where is this server located (visible on admin pages)?" "str"
ask_user "ADMINMAIL" "root@localhost.local" "What's the admin's e-mail (visible on admin pages and for Let's Encrypt)?" "email"
ask_user "PORT" "80" "Specify the port" "num"

# Validate port number
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo -e "${RED}Error: Invalid port number. Must be between 1 and 65535.${NC}"
  exit 1
fi

ask_user "SSL" "n" "Do you want Let's Encrypt to get a certificate for this server? (y/n)" "y/n"
ask_user "DO_UPDATES" "y" "Would you like to perform all OS updates? (y/n)" "y/n"

# Sanitize and validate the entered hostname(s)
HOSTNAMES=$(echo "$HOSTNAMES" | xargs)
IFS=' ' read -r -a HOSTNAMES_ARRAY <<< "$HOSTNAMES"
sanitized_domains=()
for domain in "${HOSTNAMES_ARRAY[@]}"; do
  sanitized_domain=$(echo "$domain" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  # Basic hostname validation
  if [[ ! "$sanitized_domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]; then
    echo -e "${RED}Error: Invalid hostname format: $domain${NC}"
    exit 1
  fi
  sanitized_domains+=("$sanitized_domain")
done

# Order the entered hostname(s)
HOSTNAMES_ARRAY=("${sanitized_domains[@]}")
PRIMARY_HOSTNAME="${HOSTNAMES_ARRAY[0]}"

# Build the domain flags for Certbot as an array
DOMAINS_FLAGS=()
for domain in "${HOSTNAMES_ARRAY[@]}"; do
  DOMAINS_FLAGS+=(-d "$domain")
done

# Update the OS if requested
if [ "${DO_UPDATES}" == "y" ]; then
  update_os silent
fi

# Install necessary packages
if [ "$SSL" = "y" ] && [ "$PORT" = "80" ]; then
  install_packages silent icecast2 certbot
else
  install_packages silent icecast2
fi

# Backup existing configuration if it exists
if [ -f "$ICECAST_XML" ]; then
  backup_file "$ICECAST_XML"
  echo -e "${BLUE}►► Backed up existing Icecast configuration${NC}"
fi

# Generate the initial icecast.xml configuration
echo -e "${BLUE}►► Creating Icecast configuration...${NC}"
cat << EOF > "$ICECAST_XML"
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
    <webroot>${ICECAST_WEBROOT}</webroot>
    <adminroot>/usr/share/icecast2/admin</adminroot>
    <alias source="/" destination="/status.xsl"/>
  </paths>

  <logging>
    <logsize>0</logsize>
    <loglevel>2</loglevel>
  </logging>
</icecast>
EOF

# Set capabilities so that Icecast can listen on ports 80/443
echo -e "${BLUE}►► Setting capabilities for Icecast...${NC}"
setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/icecast2

# Reload and restart the Icecast service
echo -e "${BLUE}►► Starting Icecast service...${NC}"
systemctl enable icecast2
systemctl daemon-reload
systemctl restart icecast2

# Check if Icecast started successfully
if ! systemctl is-active --quiet icecast2; then
  echo -e "${RED}Error: Icecast failed to start. Check logs with: journalctl -u icecast2${NC}"
  exit 1
fi

# SSL configuration
if [ "$SSL" = "y" ] && [ "$PORT" = "80" ]; then
  echo -e "${BLUE}►► Running Certbot to obtain SSL certificate for domains: ${HOSTNAMES_ARRAY[*]} ${NC}"

  # Create deploy hook script for better certificate handling
  DEPLOY_HOOK_SCRIPT="${LETSENCRYPT_HOOKS_DIR}/icecast2.sh"
  mkdir -p "${LETSENCRYPT_HOOKS_DIR}"
  cat << HOOK_EOF > "$DEPLOY_HOOK_SCRIPT"
#!/bin/bash
CERT_PATH="/etc/letsencrypt/live/\$RENEWED_DOMAINS"
ICECAST_PEM="${ICECAST_PEM_PATH}"

# Concatenate certificate and key
cat "\$CERT_PATH/fullchain.pem" "\$CERT_PATH/privkey.pem" > "\$ICECAST_PEM"

# Set proper permissions
chown icecast2:icecast "\$ICECAST_PEM"
chmod 600 "\$ICECAST_PEM"

# Restart Icecast
systemctl restart icecast2
HOOK_EOF
  chmod +x "$DEPLOY_HOOK_SCRIPT"

  certbot --text --agree-tos --email "$ADMINMAIL" --noninteractive --no-eff-email \
    --webroot --webroot-path="${ICECAST_WEBROOT}" \
    "${DOMAINS_FLAGS[@]}" \
    certonly

  # Check if Certbot successfully obtained a certificate and create the PEM file
  if [ -d "/etc/letsencrypt/live/$PRIMARY_HOSTNAME" ]; then
    # Run the deploy hook manually for the first time
    RENEWED_DOMAINS="$PRIMARY_HOSTNAME" bash "$DEPLOY_HOOK_SCRIPT"

    if [ -f "${ICECAST_PEM_PATH}" ]; then
      # Update icecast.xml with SSL settings
      sed -i "/<paths>/a \
    \    <ssl-certificate>${ICECAST_PEM_PATH}</ssl-certificate>" "$ICECAST_XML"

      sed -i "/<\/listen-socket>/a \
    <listen-socket>\n\
        <port>443</port>\n\
        <ssl>1</ssl>\n\
    </listen-socket>" "$ICECAST_XML"

      # Restart Icecast to apply the new configuration
      echo -e "${BLUE}►► Restarting Icecast with SSL support${NC}"
      systemctl restart icecast2
    else
      echo -e "${YELLOW} !! SSL certificate creation failed. Check permissions.${NC}"
    fi
  else
    echo -e "${YELLOW} !! SSL certificate acquisition failed. Icecast will continue running on port ${PORT}.${NC}"
  fi
else
  if [ "$SSL" = "y" ]; then
    echo -e "${YELLOW} !! SSL setup is only possible when Icecast is running on port 80. You entered port ${PORT}. Skipping SSL configuration.${NC}"
  fi
fi

# Display installation summary
echo -e "\n${GREEN}✓ Icecast installation completed!${NC}"
echo -e "${BLUE}►► Installation Summary:${NC}"
echo -e "  Primary hostname: ${CYAN}$PRIMARY_HOSTNAME${NC}"
if [ ${#HOSTNAMES_ARRAY[@]} -gt 1 ]; then
  echo -e "  Additional hostnames: ${CYAN}${HOSTNAMES_ARRAY[@]:1}${NC}"
fi
echo -e "  Admin interface: ${CYAN}http://$PRIMARY_HOSTNAME:$PORT/admin/${NC}"
echo -e "  Admin username: ${CYAN}admin${NC}"
echo -e "  Admin password: ${CYAN}$ADMINPASS${NC}"
echo -e "  Source password: ${CYAN}$SOURCEPASS${NC}"

if [ "$SSL" = "y" ] && [ "$PORT" = "80" ] && [ -f "${ICECAST_PEM_PATH}" ]; then
  echo -e "\n  ${GREEN}✓ SSL enabled${NC}"
  echo -e "  HTTPS URL: ${CYAN}https://$PRIMARY_HOSTNAME/${NC}"
  echo -e "  Certificate renewal: Automatic via Certbot"
fi

echo -e "\n${YELLOW}Important commands:${NC}"
echo -e "  View logs: ${CYAN}journalctl -u icecast2 -f${NC}"
echo -e "  Restart Icecast: ${CYAN}systemctl restart icecast2${NC}"
echo -e "  Edit configuration: ${CYAN}nano $ICECAST_XML${NC}"
if [ "$SSL" = "y" ] && [ "$PORT" = "80" ]; then
  echo -e "  Test certificate renewal: ${CYAN}certbot renew --dry-run${NC}"
fi

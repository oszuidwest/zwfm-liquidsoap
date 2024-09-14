#!/bin/bash

# Monitor Script for /var/log/liquidsoap/radio.log
# Displays current on air source and status of studio_a and studio_b.
# Status includes whether connected with audio playing or silent.
# Refreshes every second without leaving residual characters on the screen.

# Path to the log file
LOG_FILE="/var/log/liquidsoap/radio.log"

# Check if the log file exists and is readable
if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file '$LOG_FILE' does not exist."
    exit 1
fi

if [[ ! -r "$LOG_FILE" ]]; then
    echo "Error: Log file '$LOG_FILE' is not readable."
    exit 1
fi

# Function to extract the current on air source
get_current_on_air() {
    # Extract the last radio_prod switch event
    # Example lines:
    # 2024/09/14 19:27:21 [radio_prod:3] Switch to noodband.
    # 2024/09/14 19:27:46 [radio_prod:3] Switch to buffered_studio_a with transition.
    
    # Declare the variable
    local on_air
    # Assign the value
    on_air=$(grep 'radio_prod:3] Switch to' "$LOG_FILE" | tail -1 | \
        awk -F 'Switch to ' '{print $2}' | \
        sed -e 's/ with.*//' -e 's/\.$//')
    echo "${on_air:-Unknown}"
}

# Function to extract and map the latest status of a studio
get_studio_status() {
    local studio="$1"
    # Possible statuses: connected, disconnected, silence detected, audio resumed

    # Declare the variable
    local last_event
    # Assign the value
    last_event=$(grep "lang:3] ${studio}" "$LOG_FILE" | \
        grep -E 'connected|disconnected|silence detected|audio resumed' | \
        tail -1 | \
        awk -F "lang:3] ${studio} " '{print $2}')

    # Map the last event to the desired status
    case "$last_event" in
        "connected")
            echo "Connected (audio playing)"
            ;;
        "silence detected")
            echo "Connected (silent)"
            ;;
        "audio resumed")
            echo "Connected (audio playing)"
            ;;
        "disconnected")
            echo "Disconnected"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Color codes for enhanced readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clear the screen once at the start
clear

# Infinite loop to refresh every second
while true; do
    # Fetch current on air source
    CURRENT_ON_AIR=$(get_current_on_air)

    # Fetch studio statuses
    STUDIO_A_STATUS=$(get_studio_status "studio_a")
    STUDIO_B_STATUS=$(get_studio_status "studio_b")

    # Color-coding for studio_a
    case "$STUDIO_A_STATUS" in
        "Connected (audio playing)")
            STUDIO_A_DISPLAY="${GREEN}$STUDIO_A_STATUS${NC}"
            ;;
        "Connected (silent)")
            STUDIO_A_DISPLAY="${YELLOW}$STUDIO_A_STATUS${NC}"
            ;;
        "Disconnected")
            STUDIO_A_DISPLAY="${RED}$STUDIO_A_STATUS${NC}"
            ;;
        *)
            STUDIO_A_DISPLAY="$STUDIO_A_STATUS"
            ;;
    esac

    # Color-coding for studio_b
    case "$STUDIO_B_STATUS" in
        "Connected (audio playing)")
            STUDIO_B_DISPLAY="${GREEN}$STUDIO_B_STATUS${NC}"
            ;;
        "Connected (silent)")
            STUDIO_B_DISPLAY="${YELLOW}$STUDIO_B_STATUS${NC}"
            ;;
        "Disconnected")
            STUDIO_B_DISPLAY="${RED}$STUDIO_B_STATUS${NC}"
            ;;
        *)
            STUDIO_B_DISPLAY="$STUDIO_B_STATUS"
            ;;
    esac

    # Clear the screen before displaying new information
    clear

    # Display the information
    echo "==================== Radio Station Status ===================="
    echo "Timestamp: $(date '+%Y/%m/%d %H:%M:%S')"
    echo ""
    echo "Current On Air: $CURRENT_ON_AIR"
    echo ""
    echo "Studio Statuses:"
    echo -e "  studio_a: $STUDIO_A_DISPLAY"
    echo -e "  studio_b: $STUDIO_B_DISPLAY"
    echo "==============================================================="

    # Optional: Log the status to a file
    # LOG_OUTPUT="/var/log/liquidsoap/status_monitor.log"
    # echo "$(date '+%Y/%m/%d %H:%M:%S') - On Air: $CURRENT_ON_AIR | studio_a: $STUDIO_A_STATUS | studio_b: $STUDIO_B_STATUS" >> "$LOG_OUTPUT"

    # Wait for 1 second before refreshing
    sleep 1
done

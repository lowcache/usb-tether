#!/usr/bin/env zsh

# adb-tether.sh - Reverse tethering script for Arch Linux using ADB
# This script enables sharing an Android phone's data connection with a Linux laptop
# without requiring a carrier hotspot subscription

# ANSI color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Check if ADB is installed
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: ADB is not installed. Please install with:${NC}"
    echo -e "${YELLOW}sudo pacman -S android-tools${NC}"
    exit 1
fi

# Function to check ADB device connection
check_device() {
    local device_count=$(adb devices | grep -v "List" | grep -v "^$" | wc -l)
    if [[ $device_count -eq 0 ]]; then
        echo -e "${RED}No Android device detected. Please connect your phone via USB.${NC}"
        return 1
    elif [[ $device_count -gt 1 ]]; then
        echo -e "${YELLOW}Multiple devices detected. Please disconnect other devices.${NC}"
        adb devices
        return 1
    fi
    return 0
}

# Function to enable reverse tethering
enable_tethering() {
    echo -e "${BLUE}Attempting to enable reverse tethering...${NC}"
    
    # Check if USB debugging is authorized
    if ! adb shell echo "test" &> /dev/null; then
        echo -e "${YELLOW}Please check your phone and allow USB debugging if prompted.${NC}"
        sleep 3
        if ! adb shell echo "test" &> /dev/null; then
            echo -e "${RED}USB debugging not authorized. Please enable it on your phone.${NC}"
            return 1
        fi
    fi
    
    # Disable carrier tethering check
    echo -e "${BLUE}Disabling carrier tethering check...${NC}"
    adb shell settings put global tether_dun_required 0
    
    # Set USB function to RNDIS (USB tethering)
    echo -e "${BLUE}Enabling USB tethering mode...${NC}"
    adb shell svc usb setFunctions rndis
    
    # Additional settings that might help in some cases
    echo -e "${BLUE}Configuring additional tethering settings...${NC}"
    adb shell settings put global tether_offload_disabled 0
    
    echo -e "${GREEN}Reverse tethering commands executed successfully.${NC}"
    
    # Check for network interface
    echo -e "${BLUE}Checking for USB network interface...${NC}"
    sleep 2
    local usb_ifaces=$(ip link | grep -E 'usb|rndis|eth' | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$usb_ifaces" ]]; then
        echo -e "${RED}No USB network interface detected.${NC}"
        return 1
    else
        echo -e "${GREEN}Detected possible USB interfaces: ${usb_ifaces}${NC}"
    fi
    
    return 0
}

# Function to configure network
configure_network() {
    local iface=$1
    
    echo -e "${BLUE}Configuring network interface ${iface}...${NC}"
    
    # Configure network interface with a static IP
    sudo ip addr add 192.168.42.100/24 dev $iface 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}Could not set IP address. Interface might already be configured.${NC}"
    fi
    
    # Add default route
    sudo ip route add default via 192.168.42.1 dev $iface 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}Could not set default route. It might already exist.${NC}"
    fi
    
    # Configure DNS (using Google DNS as fallback)
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf.tether > /dev/null
    echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf.tether > /dev/null
    
    # Backup current resolv.conf if it exists and isn't a symlink
    if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup
    fi
    
    # Replace resolv.conf with our version
    sudo cp /etc/resolv.conf.tether /etc/resolv.conf
    
    echo -e "${GREEN}Network interface $iface configured.${NC}"
    echo -e "${BLUE}Testing network connectivity...${NC}"
    
    # Test connectivity
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        echo -e "${GREEN}Network connectivity established!${NC}"
        return 0
    else
        echo -e "${RED}No network connectivity. Please check your phone's data connection.${NC}"
        return 1
    fi
}

# Main script execution starts here
echo -e "${BLUE}=== Android Reverse Tethering Script ===${NC}"

# Check if device is connected
if ! check_device; then
    echo -e "${YELLOW}Waiting for device to be connected...${NC}"
    adb wait-for-device
    sleep 2
    if ! check_device; then
        echo -e "${RED}Device connection failed. Exiting.${NC}"
        exit 1
    fi
fi

# Get device model for better user experience
device_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
if [[ -n "$device_model" ]]; then
    echo -e "${GREEN}Connected to: $device_model${NC}"
else
    echo -e "${GREEN}Device connected${NC}"
fi

# Ask for user confirmation
echo -e "${YELLOW}This script will enable reverse tethering on your connected Android device.${NC}"
echo -e "${YELLOW}Make sure your phone has an active data connection.${NC}"
read -q "confirm?Do you want to proceed? (y/n) "
echo ""

if [[ "$confirm" != "y" ]]; then
    echo -e "${RED}Operation cancelled by user.${NC}"
    exit 0
fi

# Enable tethering
if ! enable_tethering; then
    echo -e "${RED}Failed to enable tethering. Exiting.${NC}"
    exit 1
fi

# List available interfaces and let user select
echo -e "${BLUE}Available network interfaces:${NC}"
ip link | grep -v lo | grep -E ': [a-z0-9]+:' | cut -d: -f2 | tr -d ' ' | nl

echo -e "${YELLOW}Enter the number of the interface to use (usually a USB or RNDIS interface):${NC}"
read interface_num

selected_iface=$(ip link | grep -v lo | grep -E ': [a-z0-9]+:' | cut -d: -f2 | tr -d ' ' | sed -n "${interface_num}p")

if [[ -z "$selected_iface" ]]; then
    echo -e "${RED}Invalid interface selection. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}Selected interface: $selected_iface${NC}"

# Configure network with selected interface
if configure_network "$selected_iface"; then
    echo -e "${GREEN}=== Reverse tethering successfully established! ===${NC}"
    echo -e "${BLUE}Your laptop is now using your phone's data connection.${NC}"
    echo -e "${YELLOW}To disconnect, unplug your phone or run: adb shell svc usb setFunctions${NC}"
else
    echo -e "${RED}Failed to configure network. Please check your settings.${NC}"
    exit 1
fi

exit 0
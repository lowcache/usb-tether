#!/bin/bash

# USB Tethering Script - Final Version with Automatic Interface Detection
# This script enables reliable sharing of an Android phone's data connection
# with a Linux computer without requiring carrier hotspot subscription

# ANSI color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Cleanup function to handle script termination
cleanup() {
  echo -e "${BLUE}Cleaning up...${NC}"
  if [[ -f /tmp/interfaces_before.txt ]]; then
    rm -f /tmp/interfaces_before.txt
  fi
  if [[ -f /tmp/interfaces_after.txt ]]; then
    rm -f /tmp/interfaces_after.txt
  fi
  if [[ -f /tmp/tether_speed_before.txt ]]; then
    rm -f /tmp/tether_speed_before.txt
  fi
  echo -e "${GREEN}Cleanup completed.${NC}"
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required dependencies
check_dependencies() {
  echo -e "${BLUE}Checking dependencies...${NC}"
  
  if ! command_exists adb; then
    echo -e "${RED}Error: ADB is not installed. Please install with:${NC}"
    echo -e "${YELLOW}sudo pacman -S android-tools${NC}"
    exit 1
  fi
  
  if ! command_exists ip; then
    echo -e "${RED}Error: 'ip' command not found. Please install iproute2.${NC}"
    exit 1
  fi
  
  # Check for sudo privileges
  if ! command_exists sudo; then
    echo -e "${RED}Error: 'sudo' is required for this script.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}All critical dependencies are available.${NC}"
}

# Check for connected Android device
check_device() {
  local devices
  devices=$(adb devices | grep -v "List" | grep -v "^$")
  local device_count=$(echo "$devices" | grep -c "device$")
  
  if [[ $device_count -eq 0 ]]; then
    echo -e "${RED}No Android device detected. Please connect your phone via USB.${NC}"
    return 1
  elif [[ $device_count -gt 1 ]]; then
    echo -e "${YELLOW}Multiple devices detected. Please disconnect other devices and run again.${NC}"
    echo -e "${YELLOW}Detected devices:${NC}"
    echo "$devices"
    return 1
  else
    local device_id=$(echo "$devices" | awk '{print $1}')
    echo -e "Using device: ${GREEN}$device_id${NC}"
    return 0
  fi
}

# Wait for device if not connected
wait_for_device() {
  echo -e "${YELLOW}Waiting for device to be connected...${NC}"
  adb wait-for-device
  sleep 2
}

# Get device model information
get_device_info() {
  local device_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  local android_version=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
  
  if [[ -n "$device_model" ]]; then
    echo -e "${GREEN}Connected to: $device_model (Android $android_version)${NC}"
  else
    echo -e "${GREEN}Device connected${NC}"
  fi
}

# Save current network interfaces
save_current_interfaces() {
  ip link | grep -E ': [a-z0-9]+:' | awk -F': ' '{print $2}' | cut -d@ -f1 > "$1"
}

# Detect new network interface after enabling tethering
detect_new_interface() {
  local before_file="$1"
  local after_file="$2"
  local new_interfaces
  
  # Find newly appeared interfaces
  new_interfaces=$(comm -13 <(sort "$before_file") <(sort "$after_file"))
  
  # If no new interface found, look for USB/RNDIS type interfaces
  if [[ -z "$new_interfaces" ]]; then
    echo -e "${YELLOW}No new interface detected. Looking for USB/RNDIS interfaces...${NC}"
    new_interfaces=$(grep -E 'usb|rndis|eth[0-9]+|enp.*u[0-9]+' "$after_file" || true)
  fi
  
  # If still no interface found, return all non-loopback interfaces
  if [[ -z "$new_interfaces" ]]; then
    echo -e "${YELLOW}No USB/RNDIS interface found. Listing all potential interfaces...${NC}"
    new_interfaces=$(grep -v 'lo' "$after_file")
  fi
  
  echo "$new_interfaces"
}

# Enable tethering on the device
enable_tethering() {
  echo -e "${BLUE}Attempting to enable reverse tethering...${NC}"
  
  # Save current interfaces before enabling tethering
  save_current_interfaces "/tmp/interfaces_before.txt"
  
  # Check if we can communicate with the device
  if ! adb shell echo "test" &> /dev/null; then
    echo -e "${YELLOW}Please check your phone and allow USB debugging if prompted.${NC}"
    sleep 3
    if ! adb shell echo "test" &> /dev/null; then
      echo -e "${RED}USB debugging not authorized. Please enable it on your phone.${NC}"
      return 1
    fi
  fi
  
  echo -e "${BLUE}Disabling carrier tethering check...${NC}"
  adb shell settings put global tether_dun_required 0
  
  echo -e "${BLUE}Enabling USB tethering mode...${NC}"
  adb shell svc usb setFunctions rndis
  
  echo -e "${BLUE}Configuring additional tethering settings...${NC}"
  adb shell settings put global tether_offload_disabled 0
  
  # Wait for interface to appear
  echo -e "${BLUE}Waiting for USB network interface...${NC}"
  sleep 5
  
  # Save interfaces after enabling tethering
  save_current_interfaces "/tmp/interfaces_after.txt"
  
  return 0
}

# Configure network interface with proper IP address and routing
configure_network() {
  local iface="$1"
  
  if [[ -z "$iface" ]]; then
    echo -e "${RED}No interface specified.${NC}"
    return 1
  fi
  
  # Check if interface exists
  if ! ip link show "$iface" &>/dev/null; then
    echo -e "${RED}Interface $iface does not exist.${NC}"
    return 1
  fi
  
  echo -e "${BLUE}Configuring network interface ${iface}...${NC}"
  
  # Bring up the interface if it's down
  sudo ip link set dev "$iface" up
  
  # Wait a moment for the interface to come up fully
  sleep 1
  
  # Clear any existing IP configuration
  sudo ip addr flush dev "$iface" 2>/dev/null
  
  # Add IP address with explicit broadcast
  echo -e "${BLUE}Setting IP address on $iface...${NC}"
  sudo ip addr add 192.168.42.100/24 broadcast 192.168.42.255 dev "$iface"
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to set IP address. This is a critical error.${NC}"
    return 1
  fi
  
  # Verify IP address was set
  if ! ip addr show dev "$iface" | grep -q "192.168.42.100"; then
    echo -e "${RED}IP address validation failed. Address not set correctly.${NC}"
    return 1
  else
    echo -e "${GREEN}IP address successfully configured.${NC}"
  fi
  
  # Make sure there's no conflicting default route
  echo -e "${BLUE}Setting up routing...${NC}"
  sudo ip route del default via 192.168.42.1 dev "$iface" 2>/dev/null || true
  
  # Add default route
  sudo ip route add default via 192.168.42.1 dev "$iface"
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to set default route. Check for routing conflicts.${NC}"
    return 1
  fi
  
  # Verify route was set
  if ! ip route show | grep -q "default via 192.168.42.1 dev $iface"; then
    echo -e "${RED}Route validation failed. Default route not set correctly.${NC}"
    return 1
  else
    echo -e "${GREEN}Default route successfully configured.${NC}"
  fi
  
  # Configure DNS
  echo -e "${BLUE}Setting up DNS...${NC}"
  echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf.tether > /dev/null
  echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf.tether > /dev/null
  
  if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
    sudo cp /etc/resolv.conf /etc/resolv.conf.backup
    echo -e "${YELLOW}Backed up /etc/resolv.conf to /etc/resolv.conf.backup${NC}"
  fi
  
  sudo cp /etc/resolv.conf.tether /etc/resolv.conf
  
  echo -e "${GREEN}Network interface $iface configured.${NC}"
  echo -e "${BLUE}Testing network connectivity...${NC}"
  
  # Test connectivity with more diagnostics
  if ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${GREEN}Network connectivity established!${NC}"
    return 0
  else
    echo -e "${RED}No network connectivity. Running diagnostics...${NC}"
    echo -e "${YELLOW}Current IP configuration:${NC}"
    ip addr show dev "$iface"
    echo -e "${YELLOW}Current routing table:${NC}"
    ip route show
    echo -e "${YELLOW}Trying ping with verbose output:${NC}"
    ping -c 1 -v 192.168.42.1
    
    echo -e "${RED}Please check your phone's data connection and USB tethering settings.${NC}"
    echo -e "${YELLOW}Some phones require you to enable USB tethering in the phone's settings menu.${NC}"
    return 1
  fi
}

# Optimize TCP parameters
optimize_tcp() {
  echo -e "${BLUE}Optimizing TCP parameters for better throughput...${NC}"
  
  sudo sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
  sudo sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
  
  local available_cc=$(sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | cut -d= -f2)
  if [[ "$available_cc" == *"bbr"* ]]; then
    echo -e "${GREEN}Enabling BBR congestion control (better for cellular connections)${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
  elif [[ "$available_cc" == *"cubic"* ]]; then
    echo -e "${GREEN}Enabling CUBIC congestion control${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
  fi
  
  sudo sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
  
  echo -e "${GREEN}TCP stack optimized for better throughput.${NC}"
}

# Optimize MTU for better performance
optimize_mtu() {
  local iface="$1"
  
  echo -e "${BLUE}Finding optimal MTU size for $iface...${NC}"
  
  if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    # Start with a conservative MTU that usually works
    local best_mtu=1440
    
    # Set to the more optimal MTU
    echo -e "${GREEN}Setting MTU to $best_mtu for $iface${NC}"
    sudo ip link set dev "$iface" mtu "$best_mtu" 2>/dev/null
  else
    echo -e "${YELLOW}No internet connectivity. Setting safe MTU to 1400 for $iface${NC}"
    sudo ip link set dev "$iface" mtu 1400 2>/dev/null
  fi
}

# Disable USB power management
disable_usb_power_management() {
  local iface="$1"
  
  echo -e "${BLUE}Disabling USB power management to prevent connection drops...${NC}"
  
  # Disable autosuspend for USB devices
  if [[ -w /sys/module/usbcore/parameters/autosuspend ]]; then
    sudo sh -c "echo -1 > /sys/module/usbcore/parameters/autosuspend" 2>/dev/null
    echo -e "${GREEN}Disabled USB autosuspend globally.${NC}"
  fi
  
  # Disable power management specifically for the tethering interface
  local usb_path=$(find /sys/class/net/"$iface"/device -name power -type d 2>/dev/null)
  if [[ -n "$usb_path" && -w "$usb_path/control" ]]; then
    sudo sh -c "echo on > $usb_path/control" 2>/dev/null
    echo -e "${GREEN}Disabled power management for $iface USB device.${NC}"
  fi
}

# Run a basic speed test
run_speed_test() {
  echo -e "${BLUE}Running basic connectivity test...${NC}"
  
  # Test DNS resolution
  echo -e "${BLUE}Testing DNS resolution...${NC}"
  if nslookup google.com &>/dev/null; then
    echo -e "${GREEN}DNS resolution working!${NC}"
  else
    echo -e "${RED}DNS resolution failed. Check DNS settings.${NC}"
  fi
  
  # Test HTTP connection
  echo -e "${BLUE}Testing HTTP connection...${NC}"
  if curl -s --head http://www.google.com | grep "200 OK" &>/dev/null; then
    echo -e "${GREEN}HTTP connection successful!${NC}"
  else
    echo -e "${RED}HTTP connection failed.${NC}"
  fi
  
  # Test latency
  echo -e "${BLUE}Testing connection latency...${NC}"
  ping -c 3 8.8.8.8
  
  return 0
}

# Main function
main() {
  echo -e "${GREEN}===== USB Tethering Script - Final Version =====${NC}"
  
  # Check for root privileges
  if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}This script should not be run directly as root.${NC}"
    echo -e "${YELLOW}Please run it as a regular user with sudo access.${NC}"
    exit 1
  fi
  
  # Check dependencies
  check_dependencies
  
  # Check for connected device
  if ! check_device; then
    echo -e "${YELLOW}No device detected. Waiting for device...${NC}"
    wait_for_device
    if ! check_device; then
      echo -e "${RED}Still no device detected after waiting. Exiting.${NC}"
      exit 1
    fi
  fi
  
  # Get device info
  get_device_info
  
  # Ask for user confirmation
  echo -e "${YELLOW}This script will enable USB tethering on your connected Android device.${NC}"
  echo -e "${YELLOW}Make sure your phone has an active data connection.${NC}"
  read -p "Do you want to proceed? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation cancelled by user.${NC}"
    exit 0
  fi
  
  # Enable tethering
  if ! enable_tethering; then
    echo -e "${RED}Failed to enable tethering. Exiting.${NC}"
    exit 1
  fi
  
  # Detect the appropriate interface automatically
  echo -e "${BLUE}Detecting USB tethering interface...${NC}"
  local tether_iface=$(detect_new_interface "/tmp/interfaces_before.txt" "/tmp/interfaces_after.txt" | head -1)
  
  if [[ -z "$tether_iface" ]]; then
    echo -e "${RED}Failed to detect USB tethering interface. Exiting.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Detected USB tethering interface: $tether_iface${NC}"
  
  # Configure network
  if ! configure_network "$tether_iface"; then
    echo -e "${RED}Failed to configure network. Trying alternative method...${NC}"
    
    # Alternative method: Clear interface and try again
    sudo ip addr flush dev "$tether_iface"
    sudo ip link set dev "$tether_iface" down
    sleep 2
    sudo ip link set dev "$tether_iface" up
    sleep 2
    
    # Try configure again
    if ! configure_network "$tether_iface"; then
      echo -e "${RED}Network configuration failed. Please check your device's USB tethering settings.${NC}"
      echo -e "${YELLOW}Some phones require enabling USB tethering explicitly in the phone's settings.${NC}"
      exit 1
    fi
  fi
  
  # Optimize network settings
  optimize_tcp
  optimize_mtu "$tether_iface"
  disable_usb_power_management "$tether_iface" 
  
  # Final connectivity test
  run_speed_test
  
  echo -e "${GREEN}===== USB Tethering Setup Complete =====${NC}"
  echo -e "${GREEN}Your computer is now using the phone's network connection.${NC}"
  echo -e "${BLUE}Connection details:${NC}"
  echo -e "  Interface: ${GREEN}$tether_iface${NC}"
  echo -e "  IP Address: ${GREEN}192.168.42.100${NC}"
  echo -e "  Gateway: ${GREEN}192.168.42.1${NC}"
  echo -e "  DNS: ${GREEN}8.8.8.8, 8.8.4.4${NC}"
  echo -e "${YELLOW}To disconnect, unplug your phone or run:${NC}"
  echo -e "${YELLOW}  adb shell svc usb setFunctions${NC}"
}

# Run the main function
main "$@"

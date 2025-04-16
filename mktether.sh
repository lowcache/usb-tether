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
  echo -e "{BLUE}Cleaning up temporary files...{NC}"
  rm -f /tmp/interfaces_before.txt /tmp/interfaces_after.txt /tmp/tether_speed_before.txt /etc/resolv.conf.tether 2>/dev/null
  if [[ -f /etc/resolv.conf.backup ]]; then
    echo -e "{YELLOW}Restoring original /etc/resolv.conf{NC}"
    sudo mv /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
  fi
  echo -e "{GREEN}Cleanup completed.{NC}"
}

# Check if a command exists
command_exists() {
  command -v "1" >/dev/null 2>&1
}
# Check for required dependencies
check_dependencies() {
echo -e "{BLUE}Checking dependencies...{NC}"
if ! command_exists adb; then
echo -e "{RED}Error: ADB is not installed. Please install with:{NC}"
echo -e "{YELLOW}sudo apt-get install android-tools-adb {NC} (Debian/Ubuntu)"
echo -e "{YELLOW}sudo pacman -S android-tools {NC} (Arch Linux)"
echo -e "{YELLOW}sudo dnf install android-tools {NC} (Fedora/CentOS/RHEL)"
exit 1
fi
if ! command_exists ip; then
echo -e "{RED}Error: 'ip' command not found. Please install iproute2.{NC}"
echo -e "{YELLOW}sudo apt-get install iproute2 {NC} (Debian/Ubuntu)"
echo -e "{YELLOW}sudo pacman -S iproute2 {NC} (Arch Linux)"
echo -e "{YELLOW}sudo dnf install iproute2 {NC} (Fedora/CentOS/RHEL)"
exit 1
fi
# Check for sudo privileges
if ! command_exists sudo; then
echo -e "{RED}Error: 'sudo' is required for this script.{NC}"
exit 1
fi
echo -e "{GREEN}All critical dependencies are available.{NC}"
}
# Check for connected Android device
check_device() {
local devices
devices=(adb devices | grep -v "List" | grep -v "^")
local device_count=(echo "devices" | grep -c "device")

  if [[ device_count -eq 0 ]]; then
echo -e "{RED}No Android device detected. Please connect your phone via USB and ensure USB debugging is enabled.${NC}"
    return 1
  elif [[ device_count -gt 1 ]]; then
echo -e "{YELLOW}Multiple devices detected. Please disconnect other devices and run again.{NC}"
echo -e "{YELLOW}Detected devices:${NC}"
    echo "devices"
return 1
else
local device_id=(echo "$devices" | awk '{print $1}')
    echo -e "Using device: ${GREEN}device_id{NC}"
    return 0
  fi
}

# Wait for device if not connected
wait_for_device() {
  echo -e "{YELLOW}Waiting for device to be connected...{NC}"
  adb wait-for-device
  sleep 2
}

# Get device model information
get_device_info() {
  local device_model=(adb shell getprop ro.product.model 2>/dev/null | tr -d '')
local android_version=(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '')

  if [[ -n "device_model" ]]; then
echo -e "{GREEN}Connected to: $device_model (Android android_version){NC}"
  else
    echo -e "{GREEN}Device connected{NC}"
  fi
}

# Save current network interfaces
save_current_interfaces() {
  ip link | awk -F': ' '$2 !~ lo {print $2}' | cut -d@ -f1 > "$1"
}

# Detect new network interface after enabling tethering
detect_new_interface() {
  local before_file="$1"
  local after_file="2"
local new_interfaces
# Find newly appeared interfaces that look like USB tethering interfaces
new_interfaces=(comm -23 <(sort "$before_file") <(sort "$after_file") | grep -E 'usb|rndis|eth[0-9]+|enp.*u[0-9]+')

  # If no specific interface found, try a broader search for any new non-loopback interface
  if [[ -z "new_interfaces" ]]; then
echo -e "{YELLOW}No specific USB/RNDIS interface detected. Checking for any new network interface...{NC}"
new_interfaces=(comm -23 <(sort "$before_file") <(sort "$after_file") | grep -v 'lo')
  fi

  echo "new_interfaces"
}
# Enable tethering on the device
enable_tethering() {
echo -e "{BLUE}Attempting to enable USB tethering...{NC}"
# Save current interfaces before enabling tethering
save_current_interfaces "/tmp/interfaces_before.txt"
# Check if we can communicate with the device
if ! adb shell echo "test" & > /dev/null; then
echo -e "{YELLOW}Please check your phone and ensure USB debugging is enabled and authorized.{NC}"
sleep 3
if ! adb shell echo "test" & > /dev/null; then
echo -e "{RED}USB debugging not authorized. Please authorize it on your phone when prompted.{NC}"
return 1
fi
fi
echo -e "{BLUE}Disabling carrier tethering check...{NC}"
adb shell settings put global tether_dun_required 0
echo -e "{BLUE}Enabling USB tethering mode...{NC}"
adb shell svc usb setFunctions rndis
echo -e "{BLUE}Configuring additional tethering settings...{NC}"
adb shell settings put global tether_offload_disabled 0
# Wait for interface to appear (longer wait)
echo -e "{BLUE}Waiting for USB network interface to appear...${NC}"
  sleep 10

  # Save interfaces after enabling tethering
  save_current_interfaces "/tmp/interfaces_after.txt"

  return 0
}

# Configure network interface with proper IP address and routing
configure_network() {
  local iface="$1"

  if [[ -z "iface" ]]; then
echo -e "{RED}No interface specified for configuration.${NC}"
    return 1
  fi

  # Check if interface exists
  if ! ip link show "iface" &>/dev/null; then
echo -e "{RED}Interface iface does not exist.{NC}"
    return 1
  fi

  echo -e "${BLUE}Configuring network interface {iface}...{NC}"

  # Bring up the interface if it's down
  sudo ip link set dev "$iface" up

  # Wait a moment for the interface to come up fully
  sleep 1

  # Clear any existing IP configuration
  sudo ip addr flush dev "iface" 2>/dev/null
# Add IP address with explicit broadcast
echo -e "{BLUE}Setting IP address on iface...{NC}"
  sudo ip addr add 192.168.42.100/24 broadcast 192.168.42.255 dev "$iface"

  if [[ ? -ne 0 ]]; then
echo -e "{RED}Failed to set IP address on iface. Check for conflicts or errors.{NC}"
    return 1
  fi

  # Verify IP address was set
  if ! ip addr show dev "iface" | grep -q "inet 192.168.42.100"; then
echo -e "{RED}IP address validation failed for iface. Address not set correctly.{NC}"
    return 1
  else
    echo -e "${GREEN}IP address successfully configured on iface.{NC}"
  fi

  # Make sure there's no conflicting default route
  echo -e "{BLUE}Setting up routing...{NC}"
  sudo ip route del default via 192.168.42.1 dev "$iface" 2>/dev/null || true

  # Add default route
  sudo ip route add default via 192.168.42.1 dev "$iface"

  if [[ ? -ne 0 ]]; then
echo -e "{RED}Failed to set default route via iface. Check for existing conflicting routes.{NC}"
    return 1
  fi

  # Verify route was set
  if ! ip route show | grep -q "default via 192.168.42.1 dev iface"; then
echo -e "{RED}Route validation failed. Default route via iface not set correctly.{NC}"
    return 1
  else
    echo -e "${GREEN}Default route successfully configured via iface.{NC}"
  fi

  # Configure DNS - safer approach: suggest appending or using a separate file
  echo -e "{BLUE}Setting up DNS...{NC}"
  echo -e "{YELLOW}Consider adding the following DNS servers to your /etc/resolv.conf:{NC}"
  echo -e "{YELLOW}nameserver 8.8.8.8{NC}"
  echo -e "{YELLOW}nameserver 8.8.4.4{NC}"
  echo -e "{YELLOW}Alternatively, you can create a temporary /etc/resolv.conf.tether with these entries:{NC}"
  echo "nameserver 8.8.8.8" > /etc/resolv.conf.tether
  echo "nameserver 8.8.4.4" >> /etc/resolv.conf.tether
  echo -e "{YELLOW}And then copy it to /etc/resolv.conf (you might want to back up the original first).{NC}"

  echo -e "${GREEN}Network interface iface configured.{NC}"
  echo -e "{BLUE}Testing network connectivity...{NC}"

  # Test connectivity with more diagnostics
  if ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
    echo -e "{GREEN}Network connectivity established!{NC}"
    return 0
  else
    echo -e "{RED}No network connectivity. Running diagnostics...{NC}"
    echo -e "${YELLOW}Current IP configuration on iface:{NC}"
    ip addr show dev "iface"
echo -e "{YELLOW}Current routing table:{NC}"
ip route show
echo -e "{YELLOW}Trying ping to gateway (192.168.42.1):{NC}"
ping -c 1 -W 5 192.168.42.1
echo -e "{RED}Please check your phone's data connection and USB tethering settings.{NC}"
echo -e "{YELLOW}Ensure USB tethering is enabled in your phone's settings (usually under Network & internet or Connections).{NC}"
return 1
fi
}
# Optimize TCP parameters
optimize_tcp() {
echo -e "{BLUE}Optimizing TCP parameters for better throughput...{NC}"
sudo sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sudo sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1
sudo sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
sudo sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
local available_cc=(sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | cut -d= -f2)
  if [[ "available_cc" == *"bbr"* ]]; then
echo -e "{GREEN}Enabling BBR congestion control (better for cellular connections)${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
  elif [[ "available_cc" == *"cubic"* ]]; then
echo -e "{GREEN}Enabling CUBIC congestion control${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
  fi

  sudo sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1

  echo

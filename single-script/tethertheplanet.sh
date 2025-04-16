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
  echo -e "<span class="math-inline">\{BLUE\}Cleaning up temporary files\.\.\.</span>{NC}"
  rm -f /tmp/interfaces_before.txt /tmp/interfaces_after.txt /tmp/tether_speed_before.txt /etc/resolv.conf.tether 2>/dev/null
  if [[ -f /etc/resolv.conf.backup ]]; then
    echo -e "<span class="math-inline">\{YELLOW\}Restoring original /etc/resolv\.conf</span>{NC}"
    sudo mv /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
  fi
  echo -e "<span class="math-inline">\{GREEN\}Cleanup completed\.</span>{NC}"
}

# Check if a command exists
command_exists() {
  command -v "<span class="math-inline">1" \>/dev/null 2\>&1
\}
\# Check for required dependencies
check\_dependencies\(\) \{
echo \-e "</span>{BLUE}Checking dependencies...<span class="math-inline">\{NC\}"
if \! command\_exists adb; then
echo \-e "</span>{RED}Error: ADB is not installed. Please install with:<span class="math-inline">\{NC\}"
echo \-e "</span>{YELLOW}sudo apt-get install android-tools-adb <span class="math-inline">\{NC\} \(Debian/Ubuntu\)"
echo \-e "</span>{YELLOW}sudo pacman -S android-tools <span class="math-inline">\{NC\} \(Arch Linux\)"
echo \-e "</span>{YELLOW}sudo dnf install android-tools <span class="math-inline">\{NC\} \(Fedora/CentOS/RHEL\)"
exit 1
fi
if \! command\_exists ip; then
echo \-e "</span>{RED}Error: 'ip' command not found. Please install iproute2.<span class="math-inline">\{NC\}"
echo \-e "</span>{YELLOW}sudo apt-get install iproute2 <span class="math-inline">\{NC\} \(Debian/Ubuntu\)"
echo \-e "</span>{YELLOW}sudo pacman -S iproute2 <span class="math-inline">\{NC\} \(Arch Linux\)"
echo \-e "</span>{YELLOW}sudo dnf install iproute2 <span class="math-inline">\{NC\} \(Fedora/CentOS/RHEL\)"
exit 1
fi
\# Check for sudo privileges
if \! command\_exists sudo; then
echo \-e "</span>{RED}Error: 'sudo' is required for this script.<span class="math-inline">\{NC\}"
exit 1
fi
echo \-e "</span>{GREEN}All critical dependencies are available.<span class="math-inline">\{NC\}"
\}
\# Check for connected Android device
check\_device\(\) \{
local devices
devices\=</span>(adb devices | grep -v "List" | grep -v "^<span class="math-inline">"\)
local device\_count\=</span>(echo "<span class="math-inline">devices" \| grep \-c "device</span>")

  if [[ <span class="math-inline">device\_count \-eq 0 \]\]; then
echo \-e "</span>{RED}No Android device detected. Please connect your phone via USB and ensure USB debugging is enabled.${NC}"
    return 1
  elif [[ <span class="math-inline">device\_count \-gt 1 \]\]; then
echo \-e "</span>{YELLOW}Multiple devices detected. Please disconnect other devices and run again.<span class="math-inline">\{NC\}"
echo \-e "</span>{YELLOW}Detected devices:${NC}"
    echo "<span class="math-inline">devices"
return 1
else
local device\_id\=</span>(echo "$devices" | awk '{print $1}')
    echo -e "Using device: ${GREEN}<span class="math-inline">device\_id</span>{NC}"
    return 0
  fi
}

# Wait for device if not connected
wait_for_device() {
  echo -e "<span class="math-inline">\{YELLOW\}Waiting for device to be connected\.\.\.</span>{NC}"
  adb wait-for-device
  sleep 2
}

# Get device model information
get_device_info() {
  local device_model=<span class="math-inline">\(adb shell getprop ro\.product\.model 2\>/dev/null \| tr \-d '\\r'\)
local android\_version\=</span>(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')

  if [[ -n "<span class="math-inline">device\_model" \]\]; then
echo \-e "</span>{GREEN}Connected to: $device_model (Android <span class="math-inline">android\_version\)</span>{NC}"
  else
    echo -e "<span class="math-inline">\{GREEN\}Device connected</span>{NC}"
  fi
}

# Save current network interfaces
save_current_interfaces() {
  ip link | awk -F': ' '$2 !~ /lo/ {print $2}' | cut -d@ -f1 > "$1"
}

# Detect new network interface after enabling tethering
detect_new_interface() {
  local before_file="$1"
  local after_file="<span class="math-inline">2"
local new\_interfaces
\# Find newly appeared interfaces that look like USB tethering interfaces
new\_interfaces\=</span>(comm -23 <(sort "$before_file") <(sort "$after_file") | grep -E 'usb|rndis|eth[0-9]+|enp.*u[0-9]+')

  # If no specific interface found, try a broader search for any new non-loopback interface
  if [[ -z "<span class="math-inline">new\_interfaces" \]\]; then
echo \-e "</span>{YELLOW}No specific USB/RNDIS interface detected. Checking for any new network interface...<span class="math-inline">\{NC\}"
new\_interfaces\=</span>(comm -23 <(sort "$before_file") <(sort "$after_file") | grep -v 'lo')
  fi

  echo "<span class="math-inline">new\_interfaces"
\}
\# Enable tethering on the device
enable\_tethering\(\) \{
echo \-e "</span>{BLUE}Attempting to enable USB tethering...<span class="math-inline">\{NC\}"
\# Save current interfaces before enabling tethering
save\_current\_interfaces "/tmp/interfaces\_before\.txt"
\# Check if we can communicate with the device
if \! adb shell echo "test" &\> /dev/null; then
echo \-e "</span>{YELLOW}Please check your phone and ensure USB debugging is enabled and authorized.<span class="math-inline">\{NC\}"
sleep 3
if \! adb shell echo "test" &\> /dev/null; then
echo \-e "</span>{RED}USB debugging not authorized. Please authorize it on your phone when prompted.<span class="math-inline">\{NC\}"
return 1
fi
fi
echo \-e "</span>{BLUE}Disabling carrier tethering check...<span class="math-inline">\{NC\}"
adb shell settings put global tether\_dun\_required 0
echo \-e "</span>{BLUE}Enabling USB tethering mode...<span class="math-inline">\{NC\}"
adb shell svc usb setFunctions rndis
echo \-e "</span>{BLUE}Configuring additional tethering settings...<span class="math-inline">\{NC\}"
adb shell settings put global tether\_offload\_disabled 0
\# Wait for interface to appear \(longer wait\)
echo \-e "</span>{BLUE}Waiting for USB network interface to appear...${NC}"
  sleep 10

  # Save interfaces after enabling tethering
  save_current_interfaces "/tmp/interfaces_after.txt"

  return 0
}

# Configure network interface with proper IP address and routing
configure_network() {
  local iface="$1"

  if [[ -z "<span class="math-inline">iface" \]\]; then
echo \-e "</span>{RED}No interface specified for configuration.${NC}"
    return 1
  fi

  # Check if interface exists
  if ! ip link show "<span class="math-inline">iface" &\>/dev/null; then
echo \-e "</span>{RED}Interface <span class="math-inline">iface does not exist\.</span>{NC}"
    return 1
  fi

  echo -e "${BLUE}Configuring network interface <span class="math-inline">\{iface\}\.\.\.</span>{NC}"

  # Bring up the interface if it's down
  sudo ip link set dev "$iface" up

  # Wait a moment for the interface to come up fully
  sleep 1

  # Clear any existing IP configuration
  sudo ip addr flush dev "<span class="math-inline">iface" 2\>/dev/null
\# Add IP address with explicit broadcast
echo \-e "</span>{BLUE}Setting IP address on <span class="math-inline">iface\.\.\.</span>{NC}"
  sudo ip addr add 192.168.42.100/24 broadcast 192.168.42.255 dev "$iface"

  if [[ <span class="math-inline">? \-ne 0 \]\]; then
echo \-e "</span>{RED}Failed to set IP address on <span class="math-inline">iface\. Check for conflicts or errors\.</span>{NC}"
    return 1
  fi

  # Verify IP address was set
  if ! ip addr show dev "<span class="math-inline">iface" \| grep \-q "inet 192\.168\.42\.100"; then
echo \-e "</span>{RED}IP address validation failed for <span class="math-inline">iface\. Address not set correctly\.</span>{NC}"
    return 1
  else
    echo -e "${GREEN}IP address successfully configured on <span class="math-inline">iface\.</span>{NC}"
  fi

  # Make sure there's no conflicting default route
  echo -e "<span class="math-inline">\{BLUE\}Setting up routing\.\.\.</span>{NC}"
  sudo ip route del default via 192.168.42.1 dev "$iface" 2>/dev/null || true

  # Add default route
  sudo ip route add default via 192.168.42.1 dev "$iface"

  if [[ <span class="math-inline">? \-ne 0 \]\]; then
echo \-e "</span>{RED}Failed to set default route via <span class="math-inline">iface\. Check for existing conflicting routes\.</span>{NC}"
    return 1
  fi

  # Verify route was set
  if ! ip route show | grep -q "default via 192.168.42.1 dev <span class="math-inline">iface"; then
echo \-e "</span>{RED}Route validation failed. Default route via <span class="math-inline">iface not set correctly\.</span>{NC}"
    return 1
  else
    echo -e "${GREEN}Default route successfully configured via <span class="math-inline">iface\.</span>{NC}"
  fi

  # Configure DNS - safer approach: suggest appending or using a separate file
  echo -e "<span class="math-inline">\{BLUE\}Setting up DNS\.\.\.</span>{NC}"
  echo -e "<span class="math-inline">\{YELLOW\}Consider adding the following DNS servers to your /etc/resolv\.conf\:</span>{NC}"
  echo -e "<span class="math-inline">\{YELLOW\}nameserver 8\.8\.8\.8</span>{NC}"
  echo -e "<span class="math-inline">\{YELLOW\}nameserver 8\.8\.4\.4</span>{NC}"
  echo -e "<span class="math-inline">\{YELLOW\}Alternatively, you can create a temporary /etc/resolv\.conf\.tether with these entries\:</span>{NC}"
  echo "nameserver 8.8.8.8" > /etc/resolv.conf.tether
  echo "nameserver 8.8.4.4" >> /etc/resolv.conf.tether
  echo -e "<span class="math-inline">\{YELLOW\}And then copy it to /etc/resolv\.conf \(you might want to back up the original first\)\.</span>{NC}"

  echo -e "${GREEN}Network interface <span class="math-inline">iface configured\.</span>{NC}"
  echo -e "<span class="math-inline">\{BLUE\}Testing network connectivity\.\.\.</span>{NC}"

  # Test connectivity with more diagnostics
  if ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
    echo -e "<span class="math-inline">\{GREEN\}Network connectivity established\!</span>{NC}"
    return 0
  else
    echo -e "<span class="math-inline">\{RED\}No network connectivity\. Running diagnostics\.\.\.</span>{NC}"
    echo -e "${YELLOW}Current IP configuration on <span class="math-inline">iface\:</span>{NC}"
    ip addr show dev "<span class="math-inline">iface"
echo \-e "</span>{YELLOW}Current routing table:<span class="math-inline">\{NC\}"
ip route show
echo \-e "</span>{YELLOW}Trying ping to gateway (192.168.42.1):<span class="math-inline">\{NC\}"
ping \-c 1 \-W 5 192\.168\.42\.1
echo \-e "</span>{RED}Please check your phone's data connection and USB tethering settings.<span class="math-inline">\{NC\}"
echo \-e "</span>{YELLOW}Ensure USB tethering is enabled in your phone's settings (usually under Network & internet or Connections).<span class="math-inline">\{NC\}"
return 1
fi
\}
\# Optimize TCP parameters
optimize\_tcp\(\) \{
echo \-e "</span>{BLUE}Optimizing TCP parameters for better throughput...<span class="math-inline">\{NC\}"
sudo sysctl \-w net\.core\.rmem\_max\=16777216 \>/dev/null 2\>&1
sudo sysctl \-w net\.core\.wmem\_max\=16777216 \>/dev/null 2\>&1
sudo sysctl \-w net\.ipv4\.tcp\_rmem\="4096 87380 16777216" \>/dev/null 2\>&1
sudo sysctl \-w net\.ipv4\.tcp\_wmem\="4096 65536 16777216" \>/dev/null 2\>&1
sudo sysctl \-w net\.ipv4\.tcp\_window\_scaling\=1 \>/dev/null 2\>&1
sudo sysctl \-w net\.ipv4\.tcp\_fastopen\=3 \>/dev/null 2\>&1
local available\_cc\=</span>(sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | cut -d= -f2)
  if [[ "<span class="math-inline">available\_cc" \=\= \*"bbr"\* \]\]; then
echo \-e "</span>{GREEN}Enabling BBR congestion control (better for cellular connections)${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
  elif [[ "<span class="math-inline">available\_cc" \=\= \*"cubic"\* \]\]; then
echo \-e "</span>{GREEN}Enabling CUBIC congestion control${NC}"
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
  fi

  sudo sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
  sudo sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1

  echo

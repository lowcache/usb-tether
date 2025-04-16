#!/usr/bin/env zsh

# tether-optimizer.sh - Optimize an already-active ADB tethering connection
# This script improves performance on an established tethering connection

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root or with sudo privileges.${NC}"
    echo -e "${YELLOW}Please run: sudo $0${NC}"
    exit 1
fi

# Detect active tethering connection
detect_tether_interface() {
    echo -e "${BLUE}Detecting active tethering interface...${NC}"
    
    # Look for likely tethering interfaces
    local potential_ifaces=$(ip link | grep -E 'usb|rndis|eth|ncm|enp' | grep -v "lo:" | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$potential_ifaces" ]]; then
        echo -e "${RED}No potential tethering interfaces detected.${NC}"
        return 1
    fi
    
    # Display potential interfaces and let user choose
    echo -e "${BLUE}Potential tethering interfaces found:${NC}"
    echo "$potential_ifaces" | nl
    
    local interface_count=$(echo "$potential_ifaces" | wc -l)
    if [[ $interface_count -eq 1 ]]; then
        # Only one interface, auto-select it
        local selected_iface=$(echo "$potential_ifaces")
        echo -e "${GREEN}Auto-selected interface: $selected_iface${NC}"
        echo "$selected_iface"
        return 0
    else
        # Multiple interfaces, let user select
        echo -e "${YELLOW}Multiple interfaces found. Please select which one is your tethering connection:${NC}"
        read interface_num
        
        local selected_iface=$(echo "$potential_ifaces" | sed -n "${interface_num}p")
        if [[ -z "$selected_iface" ]]; then
            echo -e "${RED}Invalid selection.${NC}"
            return 1
        fi
        
        echo -e "${GREEN}Selected interface: $selected_iface${NC}"
        echo "$selected_iface"
        return 0
    fi
}

# Apply TCP optimizations
optimize_tcp() {
    echo -e "${BLUE}Optimizing TCP parameters for better throughput...${NC}"
    
    # Increase buffer sizes
    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1
    
    # Enable window scaling
    sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
    
    # Enable fast TCP
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    
    # Try different congestion control algorithms
    local available_cc=$(sysctl net.ipv4.tcp_available_congestion_control | cut -d= -f2)
    
    if [[ "$available_cc" == *"bbr"* ]]; then
        echo -e "${GREEN}Enabling BBR congestion control (often better for cellular connections)${NC}"
        sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    elif [[ "$available_cc" == *"cubic"* ]]; then
        echo -e "${GREEN}Enabling CUBIC congestion control${NC}"
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
    fi
    
    # Enable timestamps and SACK
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    
    # Improve responsiveness
    sysctl -w net.ipv4.tcp_thin_linear_timeouts=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_early_retrans=1 >/dev/null 2>&1
    
    echo -e "${GREEN}TCP stack optimized for better throughput.${NC}"
}

# Optimize network interface
optimize_interface() {
    local iface=$1
    
    echo -e "${BLUE}Optimizing network interface ${iface}...${NC}"
    
    # Increase txqueuelen
    ip link set dev $iface txqueuelen 1000 2>/dev/null
    
    # Check if ethtool is available
    if command -v ethtool &> /dev/null; then
        # Disable energy-efficient ethernet
        ethtool --set-eee $iface eee off 2>/dev/null
        
        # Maximize ring buffer sizes
        ethtool -G $iface rx 4096 tx 4096 2>/dev/null
        
        # Offload as much as possible to hardware
        ethtool -K $iface tso on gso on gro on 2>/dev/null
    else
        echo -e "${YELLOW}ethtool not found. Skipping some optimizations.${NC}"
        echo -e "${YELLOW}Install ethtool for better performance: sudo pacman -S ethtool${NC}"
    fi
    
    # Find optimal MTU
    optimize_mtu $iface
    
    # Update route metrics to prefer this interface
    if ip route show default | grep -q $iface; then
        echo -e "${BLUE}Adjusting route metrics to prioritize tethering connection...${NC}"
        ip route del default dev $iface 2>/dev/null
        ip route add default via 192.168.42.1 dev $iface metric 50 2>/dev/null
    fi
    
    echo -e "${GREEN}Interface $iface optimized.${NC}"
}

# Find optimal MTU size
optimize_mtu() {
    local iface=$1
    
    echo -e "${BLUE}Finding optimal MTU size...${NC}"
    
    # Start with current MTU
    local current_mtu=$(ip link show $iface | grep -o "mtu [0-9]*" | awk '{print $2}')
    echo -e "${BLUE}Current MTU: $current_mtu${NC}"
    
    # Test with ping if we have connectivity
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        # Try different MTU values
        declare -a mtu_sizes=(1500 1472 1452 1440 1420 1400)
        local best_mtu=$current_mtu
        local best_time=99999
        
        for mtu in "${mtu_sizes[@]}"; do
            ip link set dev $iface mtu $mtu 2>/dev/null
            # Test with 3 pings
            local ping_result=$(ping -c 3 -s $((mtu - 28)) -M do 8.8.8.8 2>/dev/null)
            local ping_success=$?
            
            if [[ $ping_success -eq 0 ]]; then
                local ping_time=$(echo "$ping_result" | grep "avg" | awk -F '/' '{print $5}')
                if [[ -n "$ping_time" && "$ping_time" != "0.000" ]]; then
                    echo -e "${BLUE}MTU $mtu: ${ping_time}ms${NC}"
                    if (( $(echo "$ping_time < $best_time" | bc -l 2>/dev/null) )); then
                        best_time=$ping_time
                        best_mtu=$mtu
                    fi
                fi
            else
                echo -e "${YELLOW}MTU $mtu: Packet too large${NC}"
            fi
        done
        
        echo -e "${GREEN}Setting optimal MTU to $best_mtu${NC}"
        ip link set dev $iface mtu $best_mtu 2>/dev/null
    else
        echo -e "${YELLOW}No internet connectivity. Setting default MTU to 1440${NC}"
        ip link set dev $iface mtu 1440 2>/dev/null
    fi
}

# Run speed test
run_speed_test() {
    echo -e "${BLUE}Running speed test to measure performance...${NC}"
    
    # Check if we have necessary tools
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}curl not found. Cannot run speed test.${NC}"
        return 1
    fi
    
    # First test: small file to test latency
    echo -e "${BLUE}Testing connection latency...${NC}"
    local latency_start=$(date +%s.%N)
    curl -s -o /dev/null https://www.google.com/
    local latency_end=$(date +%s.%N)
    local latency=$(echo "$latency_end - $latency_start" | bc)
    echo -e "${GREEN}Connection latency: ${latency}s${NC}"
    
    # Second test: 10MB file to test throughput
    echo -e "${BLUE}Testing download throughput...${NC}"
    local dl_start=$(date +%s.%N)
    curl -s -o /dev/null http://speedtest.ftp.otenet.gr/files/test10Mb.db
    local dl_end=$(date +%s.%N)
    local dl_duration=$(echo "$dl_end - $dl_start" | bc)
    local dl_speed=$(echo "scale=2; 10 * 8 / $dl_duration" | bc)
    echo -e "${GREEN}Download speed: ${dl_speed} Mbps${NC}"
    
    # Store results for comparison
    echo "$dl_speed" > /tmp/tether_speed_before.txt
    
    return 0
}

# Disable USB power management
disable_usb_power_management() {
    echo -e "${BLUE}Disabling USB power management to prevent throttling...${NC}"
    
    # Disable autosuspend
    echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null
    
    # Set all USB devices to 'on'
    for usb_device in /sys/bus/usb/devices/*/power/control; do
        echo on > $usb_device 2>/dev/null
    done
    
    # Disable USB auto-suspend for the specific device if we can find it
    local iface=$1
    local usb_path=$(find /sys/class/net/$iface/device/driver/module -type l -name "usb*" 2>/dev/null)
    
    if [[ -n "$usb_path" ]]; then
        local usb_device=$(readlink -f $usb_path)
        echo on > $usb_device/power/control 2>/dev/null
        echo -e "${GREEN}Disabled power management for $iface USB device.${NC}"
    fi
    
    echo -e "${GREEN}USB power management disabled.${NC}"
}

# Optimize ADB connection if applicable
optimize_adb() {
    echo -e "${BLUE}Checking if we can optimize the ADB connection...${NC}"
    
    # Check if ADB is available
    if ! command -v adb &> /dev/null; then
        echo -e "${YELLOW}ADB not found. Skipping ADB optimizations.${NC}"
        return 1
    fi
    
    # Check if we have an ADB connection
    if ! adb devices | grep -q "device$"; then
        echo -e "${YELLOW}No ADB connection active. Skipping ADB optimizations.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}ADB connection found. Applying optimizations...${NC}"
    
    # Disable carrier tethering check (in case it was re-enabled)
    adb shell settings put global tether_dun_required 0 2>/dev/null
    
    # Optimize USB configuration
    adb shell setprop sys.usb.config.extra mass_storage,adb 2>/dev/null
    
    # Disable throttling
    adb shell settings put global tether_offload_disabled 0 2>/dev/null
    
    echo -e "${GREEN}ADB connection optimized.${NC}"
    return 0
}

# Compare before/after speeds
compare_speeds() {
    if [[ -f /tmp/tether_speed_before.txt ]]; then
        local speed_before=$(cat /tmp/tether_speed_before.txt)
        
        echo -e "${BLUE}Running final speed test to measure improvement...${NC}"
        local dl_start=$(date +%s.%N)
        curl -s -o /dev/null http://speedtest.ftp.otenet.gr/files/test10Mb.db
        local dl_end=$(date +%s.%N)
        local dl_duration=$(echo "$dl_end - $dl_start" | bc)
        local dl_speed=$(echo "scale=2; 10 * 8 / $dl_duration" | bc)
        
        local improvement=$(echo "scale=2; ($dl_speed - $speed_before) / $speed_before * 100" | bc)
        echo -e "${GREEN}Download speed before: ${speed_before} Mbps${NC}"
        echo -e "${GREEN}Download speed after: ${dl_speed} Mbps${NC}"
        echo -e "${GREEN}Improvement: ${improvement}%${NC}"
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== ADB Tether Connection Optimizer ===${NC}"
    echo -e "${BLUE}This script will optimize an already active tethering connection${NC}"
    
    # Detect tethering interface
    local tether_iface=$(detect_tether_interface)
    if [[ -z "$tether_iface" ]]; then
        echo -e "${RED}Could not detect tethering interface. Exiting.${NC}"
        exit 1
    fi
    
    # Measure current speed
    run_speed_test
    
    # Apply optimizations
    optimize_tcp
    optimize_interface "$tether_iface"
    disable_usb_power_management "$tether_iface"
    optimize_adb
    
    echo -e "${BLUE}All optimizations applied.${NC}"
    
    # Compare speeds
    compare_speeds
    
    echo -e "${GREEN}=== Optimization complete! ===${NC}"
    }
    main
#!/bin/bash

# nvme_set_speed.sh - Script to manage PCIe link speeds for NVMe devices
#
# This script lists available NVMe devices, displays their current and maximum PCIe link speeds,
# and allows users to set a new link speed. It supports both interactive and non-interactive modes.
#
# Usage:
#   Interactive Mode: Run the script and follow the prompts to select devices and set speeds.
#   Non-interactive Mode:
#     - Specify a device by BUS:DEV.FNC format (e.g., 01:00.0) and desired speed.
#     - Specify a device by VendorID:DeviceID format (e.g., 1344:51b7) to set all matching devices to a speed.
# Flags:
#   -h              Show this help message and exit.
#   --verbose       Enable verbose output when using -d or -v flags.
#   -d DEVICE SPEED Set speed for a specific device in BUS:DEV.FNC format.
#   -v VID:DID SPEED Set speed for all devices matching the specified VendorID:DeviceID.
#   -n Perform a dry run (show current device state without changing speed). Must be run by itself.

log_file="nvme_set_speed.log"
verbose=0  # Default to no verbose output
dry_run=0  # Default to no dry run

function show_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h              Show this help message and exit."
    echo "  --verbose       Enable verbose output when using -d or -v flags."
    echo "  -d DEVICE SPEED Set PCIe link speed for a specific device in BUS:DEV.FNC format."
    echo "  -v VID:DID SPEED Set PCIe link speed for all devices matching the specified VendorID:DeviceID."
    echo "  -n Perform a dry run (show current device state without changing speed). Must be run by itself."
    echo "  Note for the -d and -v options, a desired PCIe link speed must follow. For instance 1, 2, 3, or 4."
    echo "Interactive mode is available if no options are provided."
    echo "Examples:"
    echo " nvme_set_speed.sh -d 01:00.0 3"
    echo " nvme_set_speed.sh -v 1344:51b7 4"
    echo ""
    exit 0
}

# Log to file, and to console only if verbose mode is on
function log {
    echo "$(date) - $1" >> "$log_file"
    if (( verbose )); then
        echo "$1"
    fi
}

# Check if verbose flag is present anywhere in the arguments
for arg in "$@"; do
    if [[ "$arg" == "--verbose" ]]; then
        verbose=1
        break
    fi
done

# Validate and reformat the device identifier to standard format if needed
function check_device_format {
    dev=$1
    if [ ! -e "/sys/bus/pci/devices/$dev" ]; then
        dev="0000:$dev"  # Convert to DOMAIN:BUS:DEV.FNC format
    fi

    if [ ! -e "/sys/bus/pci/devices/$dev" ]; then
        echo "Error: Device $dev not found"
        log "Error: Device $dev not found"
        return 1
    fi

    # Adjust to the parent port if device is a bridge or switch port
    pciec=$(setpci -s "$dev" CAP_EXP+02.W)
    pt=$((("0x$pciec" & 0xF0) >> 4))
    if [[ $pt -eq 0 || $pt -eq 1 || $pt -eq 5 ]]; then
        dev=$(basename "$(dirname "$(readlink "/sys/bus/pci/devices/$dev")")")
    fi

    echo "$dev"
}

# Display NVMe devices with their details
function list_nvme_devices {
    echo -e "\nAvailable NVMe devices:"
    echo -e "No.  BUS:DEV.FNC\tVendor:Device\tCurrent Speed\tMax Speed"
    echo "-----------------------------------------------------------------"

    devices=($(lspci | grep "Non-Volatile memory controller" | awk '{print $1}'))
    num_devices=${#devices[@]}
    
    for i in "${!devices[@]}"; do
        dev="${devices[$i]}"
        vendor_device=$(lspci -ns "$dev" | awk '{print $3}')
        
        lc=$(setpci -s "$dev" CAP_EXP+0c.L)
        ls=$(setpci -s "$dev" CAP_EXP+12.W)
        
        current_speed=$(("0x$ls" & 0xF))
        max_speed=$(("0x$lc" & 0xF))
        
        printf "%-4s %-20s %-15s %-15s %-15s\n" "$((i+1))" "$dev" "$vendor_device" "$current_speed" "$max_speed"
    done
    echo
}

# Set PCIe link speed for a given device
function set_nvme_speed {
    dev=$1
    speed=$2

    log "Attempting to set PCI Express link speed for device $dev to $speed"

    dev=$(check_device_format "$dev")
    if [ $? -ne 0 ]; then
        return 1
    fi

    lc=$(setpci -s "$dev" CAP_EXP+0c.L)
    ls=$(setpci -s "$dev" CAP_EXP+12.W)
    max_speed=$(("0x$lc" & 0xF))
    current_speed=$(("0x$ls" & 0xF))

    log "Current speed: $current_speed, Max speed: $max_speed"

    if (($speed > $max_speed)); then
        log "Requested speed $speed exceeds maximum ($max_speed). Setting to max speed."
        speed=$max_speed
    fi

    # If dry run is enabled, display intended changes without applying them
    if (( dry_run )); then
        echo "Dry run: Would set device $dev speed to $speed"
        log "Dry run: Would set device $dev speed to $speed"
    else
        # Set speed if not in dry run mode
        lc2=$(setpci -s $dev CAP_EXP+30.L)
        lc2n=$(printf "%08x" $((("0x$lc2" & 0xFFFFFFF0) | $speed)))
        setpci -s "$dev" CAP_EXP+30.L="$lc2n"

        lc=$(setpci -s $dev CAP_EXP+10.L)
        lcn=$(printf "%08x" $(("0x$lc" | 0x20)))
        setpci -s "$dev" CAP_EXP+10.L="$lcn"

        sleep 0.1
        ls=$(setpci -s $dev CAP_EXP+12.W)
        new_speed=$(("0x$ls" & 0xF))
        log "Link status after change: $ls, Current link speed: $new_speed"

        if (( $new_speed == $speed )); then
            log "Speed set successfully to $new_speed"
        else
            log "Failed to set speed to $speed. Current speed: $new_speed"
        fi
    fi
}

# Process command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h) show_help ;;
        -n)  # Dry run option
            dry_run=1
            list_nvme_devices
            exit 0
            ;;
        -d) 
            device=$2
            speed=$3
            shift 3
            if [[ ! "$device" =~ ^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]$ ]]; then
                echo "Error: -d option requires a device in BUS:DEV.FNC format."
                exit 1
            fi
            set_nvme_speed "$device" "$speed"
            list_nvme_devices
            exit 0
            ;;
        -v)
            vendor_device=$2
            speed=$3
            shift 3
            if [[ ! "$vendor_device" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]]; then
                echo "Error: -v option requires a VendorID:DeviceID in ####:#### format."
                exit 1
            fi
            for dev in $(lspci -n | grep "$vendor_device" | awk '{print $1}'); do
                set_nvme_speed "$dev" "$speed"
            done
            list_nvme_devices
            exit 0
            ;;
        --verbose)
            # Already handled in the first pass; skip it here
            shift
            ;;
        *)
            echo "Invalid option: $1"
            show_help
            ;;
    esac
done

# Interactive mode if no options were provided
if (( $# == 0 )); then
    while true; do
        list_nvme_devices

        read -p "Select a device by number (or press 'q' to quit): " selection
        if [[ "$selection" == "q" ]]; then
            echo "Exiting script."
            exit 0
        elif [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > num_devices )); then
            echo "Invalid selection. Please try again."
            continue
        fi

        read -p "Enter the desired PCI express link speed (1, 2, 3, or 4): " speed
        if [[ ! "$speed" =~ ^[1-4]$ ]]; then
            echo "Invalid speed. Please try again."
            continue
        fi

        set_nvme_speed "${devices[$selection-1]}" "$speed"
    done
fi


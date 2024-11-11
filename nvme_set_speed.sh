#!/bin/bash

log_file="nvme_link_speed.log"

function log {
    echo "$(date) - $1" | tee -a "$log_file"
}

function check_device_format {
    dev=$1
    # Check if device exists in the given format
    if [ ! -e "/sys/bus/pci/devices/$dev" ]; then
        dev="0000:$dev"  # Convert to DOMAIN:BUS:DEV.FNC format
    fi

    # Verify if device still does not exist
    if [ ! -e "/sys/bus/pci/devices/$dev" ]; then
        echo "Error: Device $dev not found"
        log "Error: Device $dev not found"
        return 1
    fi

    # Determine if we need to use the parent port for this device
    pciec=$(setpci -s "$dev" CAP_EXP+02.W)
    pt=$((("0x$pciec" & 0xF0) >> 4))

    if [[ $pt -eq 0 || $pt -eq 1 || $pt -eq 5 ]]; then
        # Set to the upstream port if device is a bridge or switch port
        dev=$(basename "$(dirname "$(readlink "/sys/bus/pci/devices/$dev")")")
    fi

    echo "$dev"  # Return the correct device format
}

function list_nvme_devices {
    echo -e "\nAvailable NVMe devices:"
    echo -e "No.  BUS:DEV.FNC\tVendor:Device\tCurrent Speed\tMax Speed"
    echo "---------------------------------------------------------------------"

    devices=($(lspci | grep "Non-Volatile memory controller" | awk '{print $1}'))
    num_devices=${#devices[@]}
    
    for i in "${!devices[@]}"; do
        dev="${devices[$i]}"
        vendor_device=$(lspci -ns "$dev" | awk '{print $3}')
        
        # Get link capabilities and status
        lc=$(setpci -s "$dev" CAP_EXP+0c.L)
        ls=$(setpci -s "$dev" CAP_EXP+12.W)
        
        current_speed=$(("0x$ls" & 0xF))
        max_speed=$(("0x$lc" & 0xF))
        
        printf "%-4s %-20s %-15s %-15s %-15s\n" "$((i+1))" "$dev" "$vendor_device" "$current_speed" "$max_speed"
    done
    echo
}

function set_nvme_speed {
    dev="${devices[$1-1]}"
    speed=$2

    log "Attempting to set PCI Express link speed for device $dev to $speed"

    # Check device existence and format
    dev=$(check_device_format "$dev")
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Retrieve current and max speeds
    lc=$(setpci -s "$dev" CAP_EXP+0c.L)
    ls=$(setpci -s "$dev" CAP_EXP+12.W)
    max_speed=$(("0x$lc" & 0xF))
    current_speed=$(("0x$ls" & 0xF))

    log "Current speed: $current_speed, Max speed: $max_speed"

    if (($speed > $max_speed)); then
        log "Requested speed $speed exceeds maximum ($max_speed). Setting to max speed."
        speed=$max_speed
    fi

    # Set the target link speed in Link Control 2
    lc2=$(setpci -s $dev CAP_EXP+30.L)
    original_speed=$(("0x$lc2" & 0xF))
    lc2n=$(printf "%08x" $((("0x$lc2" & 0xFFFFFFF0) | $speed)))

    log "Original link control 2: $lc2, Original target link speed: $original_speed"
    log "Setting new target link speed to: $speed, New link control 2: $lc2n"
    setpci -s "$dev" CAP_EXP+30.L="$lc2n"

    # Trigger link retraining by setting bit 5 in Link Control register (CAP_EXP+10.L)
    lc=$(setpci -s $dev CAP_EXP+10.L)
    retrain_bit=0x20  # Bit 5 (retrain link) is 0x20
    lcn=$(printf "%08x" $(("0x$lc" | $retrain_bit)))

    log "Triggering link retraining: Original link control: $lc, New link control: $lcn"
    setpci -s "$dev" CAP_EXP+10.L="$lcn"

    # Wait briefly and check new status
    sleep 1
    ls=$(setpci -s $dev CAP_EXP+12.W)
    new_speed=$(("0x$ls" & 0xF))
    log "Link status after change: $ls, Current link speed: $new_speed"

    if (( $new_speed == $speed )); then
        log "Speed set successfully to $new_speed"
    else
        log "Failed to set speed to $speed. Current speed: $new_speed"
    fi
}

# Main loop
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

    set_nvme_speed "$selection" "$speed"
done



A utility script to manage PCI Express (PCIe) link speeds for NVMe devices. This script provides both interactive and command-line interfaces to view and modify NVMe device speeds.

## Features

- List all available NVMe devices with their current and maximum PCIe speeds
- Interactive mode for step-by-step device speed modification
- Command-line options for automated speed adjustments
- Support for targeting devices by:
  - Bus ID (BUS:DEV.FNC format)
  - Vendor/Device ID (VID:DID format)
- Dry-run mode to preview changes without applying them
- Verbose logging option
- Automatic logging of all operations to a log file

## Usage

### Interactive Mode
Simply run the script without arguments to enter interactive mode:
```bash
./nvme_set_speed.sh
```

### Command-line Options
- `-h`: Show help message and exit
- `--verbose`: Enable verbose output when using -d or -v flags
- `-d DEVICE SPEED`: Set PCIe link speed for a specific device in BUS:DEV.FNC format
- `-v VID:DID SPEED`: Set PCIe link speed for all devices matching the specified VendorID:DeviceID
- `-n`: Perform a dry run (show current device state without changing speed)

### Examples
```bash
# Set speed for specific device
./nvme_set_speed.sh -d 01:00.0 3

# Set speed for all devices of specific vendor/device ID
./nvme_set_speed.sh -v 1344:51b7 4

# Dry run to preview changes
./nvme_set_speed.sh -n
```

## Sample Output

Sample output of the script when run on a system with 10 NVME devices:
```
Available NVMe devices:
No.  BUS:DEV.FNC	Vendor:Device	Current Speed	Max Speed
---------------------------------------------------------------------
1    01:00.0              1344:51b7       3               4              
2    02:00.0              1344:51b7       3               4              
3    03:00.0              1344:51b7       3               4              
4    04:00.0              1344:51b7       3               4              
5    05:00.0              1344:51a2       3               3              
6    06:00.0              1344:51a2       3               3              
7    c1:00.0              1344:51b7       3               4              
8    c2:00.0              1344:51b7       3               4              
9    c3:00.0              1344:51b7       3               4              
10   c4:00.0              1344:51b7       3               4       

Select a device by number (or press 'q' to quit): 
```

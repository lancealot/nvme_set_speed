Adjust the PCI Express generation for a given NVME device.
This script finds all NVME devices and lists their current and max speed
Interactively modify each device and log appropriate changes and errors.

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

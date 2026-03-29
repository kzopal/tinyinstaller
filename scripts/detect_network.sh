#!/bin/sh
# detect_network.sh - detects active network interface
 
for iface in $(ls /sys/class/net); do
    if [ "$iface" != "lo" ] && [ "$iface" != "dummy0" ]; then
        echo "$iface"
        exit 0
    fi
done
echo "No network interface found."
exit 1
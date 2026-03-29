#!/bin/sh
# tinyinstaller - minimal network ISO installer
# License: AGPL-3.0
 
echo "================================"
echo "       TinyInstaller v0.1       "
echo "================================"
 
# Detect keyboard
sh scripts/detect_keyboard.sh
 
# Detect network
NET_IF=$(sh scripts/detect_network.sh)
if [ $? -ne 0 ]; then
    echo "Error: No network interface found. Exiting."
    exit 1
fi
echo "Network interface: $NET_IF"
 
# Bring up network if not already up
sudo ifconfig "$NET_IF" up
sudo udhcpc -i "$NET_IF" -q
 
# Test connectivity
echo "Testing internet connection..."
if ! wget -q --spider http://google.com; then
    echo "Error: No internet connection. Exiting."
    exit 1
fi
echo "Internet OK."
 
# Show distro menu
echo ""
echo "Available distros:"
echo "================================"
i=1
while IFS='|' read -r NAME URL; do
    case "$NAME" in
        "#"*) continue ;;
        "") continue ;;
    esac
    echo "$i) $NAME"
    i=$((i + 1))
done < config/distros.conf
echo "================================"
printf "Enter number to download (or q to quit): "
read CHOICE
 
if [ "$CHOICE" = "q" ]; then
    echo "Exiting."
    exit 0
fi
 
# Get URL from selection
i=1
ISO_URL=""
ISO_NAME=""
while IFS='|' read -r NAME URL; do
    case "$NAME" in
        "#"*) continue ;;
        "") continue ;;
    esac
    if [ "$i" = "$CHOICE" ]; then
        ISO_NAME="$NAME"
        ISO_URL="$URL"
        break
    fi
    i=$((i + 1))
done < config/distros.conf
 
if [ -z "$ISO_URL" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi
 
echo ""
echo "Selected: $ISO_NAME"
echo "URL: $ISO_URL"
printf "Download to /tmp/downloaded.iso? (y/n): "
read CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Cancelled."
    exit 0
fi
 
echo "Downloading..."
wget -O /tmp/downloaded.iso "$ISO_URL"
echo ""
echo "Download complete: /tmp/downloaded.iso"
echo "Ready for installation."
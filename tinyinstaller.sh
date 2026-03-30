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

# ================================
# WARNING
# ================================
echo ""
echo "================================"
echo "            WARNING             "
echo "================================"
echo "This will ERASE a disk completely."
echo "ALL DATA on the selected drive will be LOST."
echo "================================"
echo ""

# ================================
# DETECT SYSTEM DISK
# ================================
ROOT_DEV=$(mount | grep " on / " | awk '{print $1}' | sed 's/[0-9]*$//')
ROOT_DEV=$(basename "$ROOT_DEV")

echo "System disk detected: /dev/$ROOT_DEV"
echo "(This disk will NOT be recommended)"
echo ""

# ================================
# LIST DRIVES (PORTABLE)
# ================================
echo "Detecting drives..."
echo ""

DRIVES=""

if command -v lsblk >/dev/null 2>&1; then
    lsblk -d -o NAME,SIZE,MODEL | grep -E "sd|nvme|vd"

    DRIVES=$(lsblk -dn -o NAME | grep -E "sd|nvme|vd")

elif command -v fdisk >/dev/null 2>&1; then
    fdisk -l 2>/dev/null | grep -E "^Disk /dev/(sd|nvme|vd)"

    DRIVES=$(fdisk -l 2>/dev/null | grep -oE "/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)" | sed 's|/dev/||')

else
    echo "Fallback: scanning /sys/block"
    for dev in /sys/block/*; do
        NAME=$(basename "$dev")

        case "$NAME" in
            loop*|ram*) continue ;;
        esac

        SIZE=$(cat "$dev/size" 2>/dev/null)
        SIZE_GB=$((SIZE / 2048 / 1024))

        echo "/dev/$NAME - ${SIZE_GB}GB"

        DRIVES="$DRIVES $NAME"
    done
fi

echo ""
echo "--------------------------------"

# ================================
# RECOMMEND DRIVE (SMALLEST, NOT SYSTEM)
# ================================
RECOMMENDED=""
SMALLEST_SIZE=999999999999

for NAME in $DRIVES; do
    [ "$NAME" = "$ROOT_DEV" ] && continue

    if [ -f "/sys/block/$NAME/size" ]; then
        SIZE=$(cat "/sys/block/$NAME/size" 2>/dev/null)

        if [ "$SIZE" -lt "$SMALLEST_SIZE" ]; then
            SMALLEST_SIZE="$SIZE"
            RECOMMENDED="$NAME"
        fi
    fi
done

echo "Recommended (smallest non-system drive): /dev/$RECOMMENDED"
echo ""

# ================================
# USER INPUT
# ================================
printf "Enter target drive (example: sdb, nvme0n1): "
read TARGET

if [ -z "$TARGET" ]; then
    echo "No drive selected. Exiting."
    exit 1
fi

TARGET_PATH="/dev/$TARGET"

# Validate block device
if [ ! -b "$TARGET_PATH" ]; then
    echo "Invalid block device: $TARGET_PATH"
    exit 1
fi

# Prevent nuking system disk
if [ "$TARGET" = "$ROOT_DEV" ]; then
    echo "Refusing to write to system disk: /dev/$ROOT_DEV"
    exit 1
fi

echo ""
echo "You selected: $TARGET_PATH"
echo ""
echo "FINAL WARNING: This will DESTROY ALL DATA on $TARGET_PATH"
printf "Type 'YES' to continue: "
read FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "YES" ]; then
    echo "Cancelled."
    exit 0
fi

# ================================
# WRITE ISO
# ================================
echo ""
echo "Writing ISO to $TARGET_PATH..."
echo "This may take a while..."

sudo dd if=/tmp/downloaded.iso of="$TARGET_PATH" bs=4M status=progress oflag=sync

sync

echo ""
echo "================================"
echo "Done!"
echo "You can now boot from $TARGET_PATH"
echo "================================"

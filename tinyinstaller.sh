#!/bin/sh
# tinyinstaller - minimal network ISO installer
# License: AGPL-3.0

echo "================================"
echo "       TinyInstaller v0.1       "
echo "================================"

# Dynamically load drivers for all detected network hardware
echo "Probing network hardware..."

# PCI devices (covers physical, QEMU, VirtualBox, VMware)
for modalias in /sys/bus/pci/devices/*/modalias; do
  [ -f "$modalias" ] && modprobe -q $(cat "$modalias") 2>/dev/null
done

# USB devices (USB WiFi dongles, USB-to-Ethernet adapters)
for modalias in /sys/bus/usb/devices/*/modalias; do
  [ -f "$modalias" ] && modprobe -q $(cat "$modalias") 2>/dev/null
done

# Platform/virtio devices (some ARM boards, VirtIO-only guests)
for modalias in /sys/bus/platform/devices/*/modalias; do
  [ -f "$modalias" ] && modprobe -q $(cat "$modalias") 2>/dev/null
done

# Wait for kernel to register new interfaces
sleep 2
[ -x /sbin/mdev ] && mdev -s
[ -x /sbin/udevadm ] && udevadm trigger && udevadm settle

# Explicitly bring up any newly appeared interfaces so they show in /sys/class/net/
for iface in /sys/class/net/*/; do
  iface=$(basename "$iface")
  [ "$iface" = "lo" ] || [ "$iface" = "*" ] && continue
  ip link set "$iface" up 2>/dev/null
done

# Detect and select network interface
echo ""
echo "Available network interfaces:"
echo "================================"
i=1
for iface in $(ls /sys/class/net/); do
  [ "$iface" = "lo" ] && continue
  echo "$i) $iface"
  eval "IFACE_$i=$iface"
  i=$((i + 1))
done
echo "================================"
printf "Choose interface number: "
read IFACE_CHOICE
NET_IF=$(eval echo \$IFACE_$IFACE_CHOICE)

if [ -z "$NET_IF" ]; then
  echo "Invalid choice. Exiting."
  exit 1
fi

echo "Selected: $NET_IF"

# If WiFi, ask for credentials
if echo "$NET_IF" | grep -qE "^wl"; then
  echo "WiFi interface detected."
  printf "Enter WiFi SSID: "
  read SSID
  printf "Enter WiFi password: "
  read PASS
  echo ""
  wpa_passphrase "$SSID" "$PASS" > /tmp/wpa.conf
  wpa_supplicant -B -i "$NET_IF" -c /tmp/wpa.conf
  sleep 3
fi

ip link set "$NET_IF" up
udhcpc -i "$NET_IF" -q -t 10

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
  case "$NAME" in "#"*) continue ;; "") continue ;; esac
  echo "$i) $NAME"
  i=$((i + 1))
done < /opt/config/distros.conf
echo "================================"
printf "Enter number to download (or q to quit): "
read CHOICE

[ "$CHOICE" = "q" ] && echo "Exiting." && exit 0

i=1
ISO_URL=""
ISO_NAME=""
while IFS='|' read -r NAME URL; do
  case "$NAME" in "#"*) continue ;; "") continue ;; esac
  if [ "$i" = "$CHOICE" ]; then
    ISO_NAME="$NAME"
    ISO_URL="$URL"
    break
  fi
  i=$((i + 1))
done < /opt/config/distros.conf

if [ -z "$ISO_URL" ]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

echo ""
echo "Selected: $ISO_NAME"
echo "URL: $ISO_URL"
printf "Download to /tmp/downloaded.iso? (y/n): "
read CONFIRM
[ "$CONFIRM" != "y" ] && echo "Cancelled." && exit 0

echo "Downloading..."
wget -O /tmp/downloaded.iso "$ISO_URL"
echo ""
echo "Download complete: /tmp/downloaded.iso"

echo ""
echo "================================"
echo "            WARNING             "
echo "================================"
echo "This will ERASE a disk completely."
echo "ALL DATA on the selected drive will be LOST."
echo "================================"
echo ""

ROOT_DEV=$(mount | grep " on / " | awk '{print $1}' | sed 's/[0-9]*$//')
ROOT_DEV=$(basename "$ROOT_DEV")
echo "System disk detected: /dev/$ROOT_DEV"
echo "(This disk will NOT be recommended)"
echo ""

echo "Detecting drives..."
echo ""
DRIVES=""
echo "Fallback: scanning /sys/block"
for dev in /sys/block/*; do
  NAME=$(basename "$dev")
  case "$NAME" in loop*|ram*) continue ;; esac
  SIZE=$(cat "$dev/size" 2>/dev/null)
  SIZE_GB=$((SIZE / 2048 / 1024))
  echo "/dev/$NAME - ${SIZE_GB}GB"
  DRIVES="$DRIVES $NAME"
done

echo ""
echo "--------------------------------"

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

printf "Enter target drive (example: sdb, nvme0n1): "
read TARGET

[ -z "$TARGET" ] && echo "No drive selected. Exiting." && exit 1

TARGET_PATH="/dev/$TARGET"

[ ! -b "$TARGET_PATH" ] && echo "Invalid block device: $TARGET_PATH" && exit 1
[ "$TARGET" = "$ROOT_DEV" ] && echo "Refusing to write to system disk." && exit 1

echo ""
echo "You selected: $TARGET_PATH"
echo ""
echo "FINAL WARNING: This will DESTROY ALL DATA on $TARGET_PATH"
printf "Type 'YES' to continue: "
read FINAL_CONFIRM

[ "$FINAL_CONFIRM" != "YES" ] && echo "Cancelled." && exit 0

echo ""
echo "Writing ISO to $TARGET_PATH..."
echo "This may take a while..."
dd if=/tmp/downloaded.iso of="$TARGET_PATH" bs=4M status=progress oflag=sync
sync

echo ""
echo "================================"
echo "Done! You can now boot from $TARGET_PATH"
echo "================================"

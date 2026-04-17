#!/bin/sh
# tinyinstaller - minimal network ISO installer
# License: AGPL-3.0

# hopefully this works
set -eu
if ! command -v udhcpc >/dev/null 2>&1; then
  if command -v dhclient >/dev/null 2>&1; then
    udhcpc() { dhclient "$2"; }
  else
    echo "Error: udhcpc not found."
    exit 1
  fi
fi

 echo "================================"
 echo "       TinyInstaller v0.1       "
 echo "================================"

# --- Load kernel modules safely ---
echo "Probing hardware..."

if ! lsmod | grep -q .; then
  depmod -a "$(uname -r)" 2>/dev/null || true
fi

for modalias in /sys/bus/*/devices/*/modalias; do
  [ -f "$modalias" ] || continue
  alias=$(cat "$modalias" 2>/dev/null || true)
  [ -n "$alias" ] && modprobe -q "$alias" 2>/dev/null || true
done

# settle devices
sleep 2
[ -x /sbin/mdev ] && mdev -s || true
[ -x /sbin/udevadm ] && udevadm trigger && udevadm settle || true

# bring up interfaces
for iface in /sys/class/net/*; do
  iface=$(basename "$iface")
  [ "$iface" = "lo" ] && continue
  ip link set "$iface" up 2>/dev/null || true
done

# --- Connectivity check (early fail) ---
if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  echo "No internet."
fi

# --- Interface selection ---
echo ""
echo "Available network interfaces:"
echo "================================"
i=1
for iface in /sys/class/net/*; do
  iface=$(basename "$iface")
  [ "$iface" = "lo" ] && continue
  echo "$i) $iface"
  eval "IFACE_$i=$iface"
  i=$((i + 1))
done
echo "================================"
printf "Choose interface number: "
read IFACE_CHOICE
NET_IF=$(eval echo \$IFACE_$IFACE_CHOICE)

[ -z "$NET_IF" ] && echo "Invalid choice." && exit 1

echo "Selected: $NET_IF"

# WiFi handling
case "$NET_IF" in
  wl*)
    printf "SSID: "
    read SSID
    printf "Password: "
    read PASS
    wpa_passphrase "$SSID" "$PASS" > /tmp/wpa.conf
    wpa_supplicant -B -i "$NET_IF" -c /tmp/wpa.conf
    sleep 3
    ;;
esac

ip link set "$NET_IF" up || true
udhcpc -i "$NET_IF" -q -t 10

# --- Connectivity test ---
echo "Testing internet..."
if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  echo "Error: No internet connection."
  exit 1
fi

echo "Internet OK."

# --- Distro selection ---
echo ""
echo "Available distros:"
echo "================================"
i=1
while IFS='|' read -r NAME URL; do
  case "$NAME" in ""|\#*) continue ;; esac
  echo "$i) $NAME"
  i=$((i + 1))
done < /opt/config/distros.conf
echo "================================"
printf "Enter number (or q): "
read CHOICE

[ "$CHOICE" = "q" ] && exit 0

# resolve selection
i=1
ISO_URL=""
ISO_NAME=""
while IFS='|' read -r NAME URL; do
  case "$NAME" in ""|\#*) continue ;; esac
  if [ "$i" = "$CHOICE" ]; then
    ISO_NAME="$NAME"
    ISO_URL="$URL"
    break
  fi
  i=$((i + 1))
done < /opt/config/distros.conf

[ -z "$ISO_URL" ] && echo "Invalid selection." && exit 1

echo "Selected: $ISO_NAME"

printf "Download to /tmp/downloaded.iso? (y/n): "
read CONFIRM
[ "$CONFIRM" != "y" ] && exit 0

wget -O /tmp/downloaded.iso "$ISO_URL"

# --- Drive detection ---
ROOT_DEV=$(mount | awk '$3=="/" {print $1}' | sed 's/[0-9]*$//')
ROOT_DEV=$(basename "$ROOT_DEV")

echo "System disk: /dev/$ROOT_DEV"

echo "Available drives:"
DRIVES=""
for dev in /sys/block/*; do
  NAME=$(basename "$dev")
  case "$NAME" in loop*|ram*) continue ;; esac
  SIZE=$(cat "$dev/size" 2>/dev/null || echo 0)
  SIZE_GB=$((SIZE / 2048 / 1024))
  echo "/dev/$NAME - ${SIZE_GB}GB"
  DRIVES="$DRIVES $NAME"
done

# recommend smallest non-root
RECOMMENDED=""
SMALLEST=999999999999
for NAME in $DRIVES; do
  [ "$NAME" = "$ROOT_DEV" ] && continue
  SIZE=$(cat "/sys/block/$NAME/size" 2>/dev/null || echo 0)
  [ "$SIZE" -lt "$SMALLEST" ] && SMALLEST="$SIZE" && RECOMMENDED="$NAME"
done

echo "Recommended: /dev/$RECOMMENDED"

printf "Target drive: "
read TARGET

TARGET_PATH="/dev/$TARGET"

[ ! -b "$TARGET_PATH" ] && echo "Invalid device" && exit 1
[ "$TARGET" = "$ROOT_DEV" ] && echo "Refusing system disk" && exit 1

printf "Type YES to confirm: "
read FINAL
[ "$FINAL" != "YES" ] && exit 0

# --- Write image ---
echo "Writing..."
dd if=/tmp/downloaded.iso of="$TARGET_PATH" bs=4M status=progress oflag=sync
sync

echo "Done. Boot from $TARGET_PATH"

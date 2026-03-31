#!/bin/bash
set -eu

# ================================
# TinyInstaller ISO Build Script
# ================================

BUILD_DIR="/root/tinyinstaller"
INITRD_DIR="$BUILD_DIR/initrd"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_ISO="/root/tinyinstaller.iso"
REPO_URL="https://github.com/kzopal/tinyinstaller/archive/refs/heads/main.zip"
KERNEL_URL="http://distro.ibiblio.org/tinycorelinux/17.x/x86_64/release/distribution_files/vmlinuz64"

# --- Validate paths ---
[ -n "$BUILD_DIR" ] || { echo "BUILD_DIR empty"; exit 1; }
case "$BUILD_DIR" in
  /*) ;;
  *) echo "BUILD_DIR must be absolute"; exit 1 ;;
esac

echo "================================"
echo "   TinyInstaller ISO Builder    "
echo "================================"

# ================================
# INSTALL DEPENDENCIES
# ================================
echo "[1/7] Installing dependencies..."
apt-get update -y > /dev/null
apt-get install -y busybox-static cpio gzip xorriso isolinux syslinux wget curl unzip > /dev/null

# ================================
# CLEAN + CREATE BUILD TREE
# ================================
echo "[2/7] Preparing build tree..."
rm -rf "$BUILD_DIR"

# create everything upfront (prevents all cp failures)
mkdir -p \
  "$INITRD_DIR/bin" \
  "$INITRD_DIR/dev" \
  "$INITRD_DIR/etc" \
  "$INITRD_DIR/proc" \
  "$INITRD_DIR/sys" \
  "$INITRD_DIR/tmp" \
  "$INITRD_DIR/opt/scripts" \
  "$INITRD_DIR/opt/config" \
  "$ISO_DIR/boot/isolinux"

# ================================
# DOWNLOAD LATEST REPO
# ================================
echo "[3/7] Downloading tinyinstaller..."
wget -q -O /tmp/tinyinstaller.zip "$REPO_URL"
unzip -q /tmp/tinyinstaller.zip -d /tmp/

# ensure dirs exist (defensive, idempotent)
mkdir -p "$INITRD_DIR/opt" "$INITRD_DIR/opt/scripts" "$INITRD_DIR/opt/config"

cp /tmp/tinyinstaller-main/tinyinstaller.sh "$INITRD_DIR/opt/tinyinstaller.sh"
cp /tmp/tinyinstaller-main/scripts/detect_network.sh "$INITRD_DIR/opt/scripts/"
cp /tmp/tinyinstaller-main/scripts/detect_keyboard.sh "$INITRD_DIR/opt/scripts/"
cp /tmp/tinyinstaller-main/config/distros.conf "$INITRD_DIR/opt/config/"

rm -rf /tmp/tinyinstaller-main /tmp/tinyinstaller.zip

# Fix paths and remove sudo
sed -i 's|scripts/detect_network.sh|/opt/scripts/detect_network.sh|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's|scripts/detect_keyboard.sh|/opt/scripts/detect_keyboard.sh|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's|config/distros.conf|/opt/config/distros.conf|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's/sudo //g' "$INITRD_DIR/opt/tinyinstaller.sh" "$INITRD_DIR/opt/scripts/"*.sh
chmod +x "$INITRD_DIR/opt/tinyinstaller.sh" "$INITRD_DIR/opt/scripts/"*.sh

# ================================
# SET UP BUSYBOX (static only)
# ================================
echo "[4/7] Setting up busybox..."
cp /bin/busybox "$INITRD_DIR/bin/busybox"

cd "$INITRD_DIR/bin"
for cmd in sh ash ls cat mkdir mount umount echo sleep ip udhcpc wget grep basename; do
  ln -sf busybox "$cmd"
done
cd "$BUILD_DIR"

# ================================
# CREATE INIT SCRIPT
# ================================
echo "[5/7] Creating init script..."
cat > "$INITRD_DIR/init" << 'INITEOF'
#!/bin/busybox sh

# DNS fallback
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# Mount /proc, /sys, /dev
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev || true
/bin/busybox mdev -s || true
[ -x /sbin/udevadm ] && udevadm trigger && udevadm settle || true
sleep 2  # allow devices to settle

# load modules safely
for m in /sys/bus/*/devices/*/modalias; do
  [ -f "$m" ] || continue
  modprobe "$(cat "$m")" 2>/dev/null || true
done

# bring interfaces up
for i in /sys/class/net/*; do
  iface=$(basename "$i")
  [ "$iface" = "lo" ] && continue
  ip link set "$iface" up 2>/dev/null
done

# build interface list safely
set -- $(ls /sys/class/net/ | grep -v '^lo$')

echo "Available network interfaces:"
echo "================================"
i=1
for iface in "$@"; do
  echo "$i) $iface"
  i=$((i + 1))
done
echo "================================"
printf "Choose interface number: "
read IFACE_CHOICE

n=1
for iface in "$@"; do
  if [ "$n" = "$IFACE_CHOICE" ]; then
    NET_IF="$iface"
    break
  fi
  n=$((n + 1))
done

[ -z "${NET_IF:-}" ] && echo "Invalid choice" && exec sh

ip link set "$NET_IF" up
udhcpc -i "$NET_IF" -q -t 10

cd /opt
sh tinyinstaller.sh
sh
INITEOF

chmod +x "$INITRD_DIR/init"

# ================================
# DOWNLOAD KERNEL
# ================================
echo "[6/7] Downloading kernel..."
wget -q -O "$ISO_DIR/boot/vmlinuz" "$KERNEL_URL"

# ================================
# PACK INITRD
# ================================
cd "$INITRD_DIR"
find . | cpio -o -H newc | gzip -9 > "$ISO_DIR/boot/core.gz"
cd "$BUILD_DIR"

# ================================
# SET UP BOOTLOADER
# ================================
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/boot/isolinux/" 2>/dev/null || \
cp /usr/lib/syslinux/isolinux.bin "$ISO_DIR/boot/isolinux/"

cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO_DIR/boot/isolinux/"
chmod 644 "$ISO_DIR/boot/isolinux/isolinux.bin"

cat > "$ISO_DIR/boot/isolinux/isolinux.cfg" << 'EOF'
DEFAULT tinyinstaller
LABEL tinyinstaller
  KERNEL /boot/vmlinuz
  INITRD /boot/core.gz
  APPEND quiet init=/init
EOF

# ================================
# BUILD ISO
# ================================
echo "[7/7] Building ISO..."
xorriso -as mkisofs \
  -o "$OUTPUT_ISO" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  "$ISO_DIR"

echo ""
echo "================================"
echo "Build complete!"
echo "ISO: $OUTPUT_ISO"
echo "Size: $(du -sh "$OUTPUT_ISO" | cut -f1)"
echo "================================"

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
# CLEAN OLD BUILD
# ================================
echo "[2/7] Cleaning old build..."
rm -rf "$BUILD_DIR"
mkdir -p "$INITRD_DIR"/{bin,dev,etc,proc,sys,tmp,opt/scripts,opt/config}
mkdir -p "$ISO_DIR"/boot/isolinux

# ================================
# DOWNLOAD LATEST REPO
# ================================
echo "[3/7] Downloading latest tinyinstaller from GitHub..."
wget -q -O /tmp/tinyinstaller.zip "$REPO_URL"
unzip -q /tmp/tinyinstaller.zip -d /tmp/
cp /tmp/tinyinstaller-main/tinyinstaller.sh "$INITRD_DIR/opt/tinyinstaller.sh"
cp /tmp/tinyinstaller-main/scripts/detect_network.sh "$INITRD_DIR/opt/scripts/detect_network.sh"
cp /tmp/tinyinstaller-main/scripts/detect_keyboard.sh "$INITRD_DIR/opt/scripts/detect_keyboard.sh"
cp /tmp/tinyinstaller-main/config/distros.conf "$INITRD_DIR/opt/config/distros.conf"
rm -rf /tmp/tinyinstaller-main /tmp/tinyinstaller.zip

# Fix paths and remove sudo
sed -i 's|scripts/detect_network.sh|/opt/scripts/detect_network.sh|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's|scripts/detect_keyboard.sh|/opt/scripts/detect_keyboard.sh|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's|config/distros.conf|/opt/config/distros.conf|g' "$INITRD_DIR/opt/tinyinstaller.sh"
sed -i 's/sudo //g' "$INITRD_DIR/opt/tinyinstaller.sh" "$INITRD_DIR/opt/scripts/"*.sh
chmod +x "$INITRD_DIR/opt/tinyinstaller.sh" "$INITRD_DIR/opt/scripts/"*.sh

# ================================
# SET UP BUSYBOX
# ================================
echo "[4/7] Setting up busybox..."
cp /bin/busybox "$INITRD_DIR/bin/busybox"
cd "$INITRD_DIR/bin"
for cmd in sh ash ls cat mkdir mount umount echo sleep ip udhcpc wget; do
  ln -sf busybox "$cmd"
done
cd "$BUILD_DIR"

# ================================
# CREATE INIT SCRIPT
# ================================
echo "[5/7] Creating init script..."
cat > "$INITRD_DIR/init" << 'INITEOF'
#!/bin/busybox sh

/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev || /bin/busybox mdev -s

# minimal DNS fallback
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# load kernel modules via modalias
for m in /sys/bus/*/devices/*/modalias; do
  [ -f "$m" ] || continue
  modprobe "$(cat "$m")" 2>/dev/null
done

# bring interfaces up
for i in /sys/class/net/*; do
  iface=$(basename "$i")
  [ "$iface" = "lo" ] && continue
  /bin/busybox ip link set "$iface" up 2>/dev/null
done

# simple interface list (no eval)
set -- $(/bin/busybox ls /sys/class/net/ | /bin/busybox grep -v '^lo$')

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

# resolve selection
n=1
for iface in "$@"; do
  if [ "$n" = "$IFACE_CHOICE" ]; then
    NET_IF="$iface"
    break
  fi
  n=$((n + 1))
done

[ -z "${NET_IF:-}" ] && echo "Invalid choice." && exec /bin/busybox sh

echo "Bringing up $NET_IF..."
/bin/busybox ip link set "$NET_IF" up
/bin/busybox udhcpc -i "$NET_IF" -q -t 10

cd /opt
/bin/busybox sh tinyinstaller.sh
/bin/busybox sh
INITEOF
chmod +x "$INITRD_DIR/init"

# ================================
# DOWNLOAD KERNEL
# ================================
echo "[6/7] Downloading kernel and packing initrd..."
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
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/boot/isolinux/" || cp /usr/lib/syslinux/isolinux.bin "$ISO_DIR/boot/isolinux/"
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
echo ""
echo "Test with:"
echo "qemu-system-x86_64 -cdrom $OUTPUT_ISO -m 512M -boot d -netdev user,id=net0 -device e1000,netdev=net0"

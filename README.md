# tinyinstaller
A internet installer for big ISOs with tiny USB drives.
Use the script or burn the provided ISO to a USB drive.

## How It Works
tinyinstaller boots a minimal Tiny Core Linux environment, detects your network interface, and downloads a full Linux distro ISO directly to your target disk — all from a tiny USB or ISO under 50 MB.

## Requirements
- USB drive or VM with network access
- Internet connection (wired recommended)
- Target disk with enough space for your chosen distro

## Usage
```sh
cd tinyinstaller
sh tinyinstaller.sh
```
Follow the prompts to select and download a distro.

## Supported Distros
See `config/distros.conf` for the full list. Currently includes:
- Debian 13 Trixie Netinstall
- Debian 12 Bookworm Netinstall
- Arch Linux
- CachyOS Desktop
- Linux Mint 22.3 Cinnamon
- Pop!_OS 24.04
- Ubuntu 24.04 Desktop
- Fedora 43 Workstation
- NixOS 25.11 Minimal
- FreeBSD 15.0
- openSUSE Tumbleweed
- Alpine Linux 3.23.3

## Project Structure
```
tinyinstaller/
├── LICENSE
├── README.md
├── tinyinstaller.sh        # Main entry point
├── config/
│   └── distros.conf        # List of downloadable distros
├── scripts/
│   ├── detect_network.sh   # Detects active network interface
│   └── detect_keyboard.sh  # Detects keyboard input device
└── iso_build/              # For future custom ISO builds
    ├── boot/
    ├── rootfs/
    └── initrd/
```

## Environment
Built on **Tiny Core Linux Core 17.0** (20 MB, CLI only).

### SSH Auto-Start on Boot
SSH is configured to start automatically on every boot via `/opt/bootlocal.sh`:
```sh
/usr/local/etc/init.d/openssh start
```

#### How it was set up:
1. Installed openssh via `tce-load -wi openssh`
2. Generated host keys with `sudo ssh-keygen -A`
3. Copied default config: `sshd_config.orig` → `sshd_config`
4. Added openssh to `/mnt/sda1/tce/onboot.lst` so it loads on boot
5. Added sshd start command to `/opt/bootlocal.sh`
6. Saved `/etc/shadow` and `/usr/local/etc/ssh` to `.filetool.lst` for persistence
7. Backed up with `filetool.sh -b`

#### Connecting:
```sh
ssh tc@127.0.0.1 -p 2222
```
Port forwarding: Host 2222 → Guest 22 (configured in VirtualBox NAT settings)

### Persistence
Files are saved to `/mnt/sda1/tce/mydata.tgz` on shutdown/backup.
`/home/tc` and `/opt` persist across reboots via `filetool.sh`.

## Testing in VirtualBox
- Type: Other Linux (64-bit)
- RAM: 512 MB minimum
- Disk: 10 GB VDI
- Network: NAT
- Boot: Core-17.0.iso

## License
AGPL-3.0 — see LICENSE for details.
Copyleft applies if run as a network service.
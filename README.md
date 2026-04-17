# tinyinstaller
A internet installer for big ISOs with tiny USB drives.
Use the script or burn the provided ISO to a USB drive.

## How It Works
tinyinstaller is a script that lets you choose from a large range of linux distros and utilities downloads it directly to your target disk all from a tiny shell script. It is designed to be light weight and tiny.

## Requirements
- USB drive or VM with network access
- Internet connection (wired recommended)
- Target disk with enough space for your chosen distro

## Usage
You might need to install busybox
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
- Ubuntu 24.04 LTS Server  
- Fedora 43 Workstation  
- NixOS 25.11 Minimal  
- FreeBSD 15.0  
- NetBSD 10.1  
- openSUSE Tumbleweed  
- Alpine Linux 3.23.3  
- Void Linux  
- Gentoo Minimal  
- Gentoo LiveGUI  
- Kali Linux 2025.4  
- System Rescue  

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


## Tested and working on
Script:
-Debian 13
-Tiny Core Linux

ISO:
-tbd

## License
AGPL-3.0 — see LICENSE for details.
Copyleft applies if run as a network service.

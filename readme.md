# 🛠️ `kernelkure.sh` — Linux System Diagnostic & Repair Tool

> **Production-grade, interactive, root-privileged Bash script for diagnosing and repairing common Linux system failures — from boot issues to package corruption, disk errors, and log analysis.**

---

## ✅ Overview

`kernelkure.sh` is a comprehensive, modular, and safe-to-use diagnostic and repair tool designed for **Debian/Ubuntu**, **RHEL/Fedora/CentOS/Rocky/AlmaLinux**, and **Arch-based** systems. It provides guided, step-by-step repairs with user confirmation before any destructive action, automatic configuration backups, detailed logging, and color-coded terminal output for clarity.

Whether you’re facing:
- A **black screen or GRUB failure**
- **Broken packages or lock files**
- **Full disks or corrupted filesystems**
- **Mysterious system crashes or service failures**

…this script helps you **diagnose, fix, and recover** — safely and systematically.

---

## 📦 Supported Distributions

| Family       | Distributions                                                                 |
|--------------|-------------------------------------------------------------------------------|
| **Debian**   | Ubuntu, Debian, Linux Mint, Pop!_OS, Kali, MX Linux, Raspberry Pi OS, etc.     |
| **RHEL**     | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux, Fedora                    |
| **Arch**     | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix                               |
| *Limited*    | openSUSE, Gentoo, Void (basic detection only — full support in future)        |

---

## ⚙️ Requirements

- **Root privileges** (`sudo`)
- **Bash 4.0+**
- Common system utilities: `lsblk`, `grep`, `awk`, `sed`, `findmnt`, `journalctl`, `dmesg`, etc.
- Package managers: `apt`, `dnf/yum`, or `pacman` (depending on distro)
- Disk tools: `fsck`, `blkid`
- Optional: `lspci`, `nvidia-xconfig` (for GPU diagnostics)

---

## 🚀 Quick Start

```bash
# Download or create the script
chmod +x kernelkure.sh

# Run interactively (recommended for beginners)
sudo ./kernelkure.sh

# Or run specific modules directly:
sudo ./sys-repair.sh --boot      # Fix boot/display issues
sudo ./sys-repair.sh --packages  # Repair broken packages
sudo ./sys-repair.sh --disk      # Check disk health
sudo ./sys-repair.sh --logs      # Extract critical logs
sudo ./sys-repair.sh --all       # Run everything (interactive prompts)
```

---

## 🧩 Modules Explained

### 1. 🔌 **Boot / Display Repair**

- **GRUB Reinstallation**: Auto-detects boot device (UEFI/BIOS), backs up configs, reinstalls bootloader.
- **GPU Conflict Detection**: Checks for NVIDIA vs Nouveau driver conflicts, AMD vs Radeon, Intel i915.
- **Black Screen Fixes**: Audits Xorg/Wayland configs, checks display manager status, suggests kernel parameters.
- **X11/Wayland Configuration**: Regenerates configs, disables problematic overrides, enables DRM modesetting.

> 💡 *Perfect for when your system boots but shows a black screen or fails to start GUI.*

---

### 2. 📦 **Package Manager Fixes**

- **Lock Cleanup**: Removes stale `apt/dpkg`, `dnf/yum/rpm`, or `pacman` locks safely.
- **Dependency Repair**: Runs `--fix-broken`, `distro-sync`, `pacman -Sy`, etc.
- **Orphaned Packages**: Identifies and optionally removes unused packages.
- **Cache Cleanup**: Frees space by cleaning package caches.

> 🛑 *Never manually delete `/var/lib/dpkg/lock` again — let the script handle it safely.*

---

### 3. 💾 **Disk & Filesystem Health**

- **Space Analysis**: Highlights partitions >80% full, suggests cleanup commands.
- **Inode Usage**: Warns if inode tables are exhausted.
- **fstab Validator**: Checks for invalid UUIDs, missing mount points, syntax errors.
- **Filesystem Check (fsck)**: Scans unmounted partitions for corruption, auto-fixes where possible.
- **Read-only Root FS Alert**: Detects emergency read-only mounts indicating serious errors.

> 📊 *Ideal for servers or workstations running out of space or showing I/O errors.*

---

### 4. 📄 **Critical Log Extraction**

- **System Journal Errors**: Extracts last 50 critical systemd journal entries.
- **Kernel Issues**: Searches for panics, oops, segfaults in `dmesg`.
- **OOM Events**: Finds Out-of-Memory killer activity.
- **Failed Services**: Lists systemd units that failed to start.
- **Service Error Summary**: Shows top 10 services generating errors.

> 🕵️ *Essential for post-mortem analysis or preparing bug reports.*

---

## 📁 Backup & Logging

### Automatic Backups

Before modifying any config file, the script creates timestamped backups under:

```
/var/backup/sys-repair-YYYYMMDD_HHMMSS/
```

Example structure:
```
/var/backup/sys-repair-20250405_143022/
├── etc/
│   ├── default/grub
│   └── grub.d/
├── boot/
│   └── grub/
│       └── grub.cfg
└── etc/X11/xorg.conf.d/
```

You can restore any file manually:
```bash
cp /var/backup/sys-repair-*/etc/default/grub /etc/default/grub
```

---

### Detailed Logging

All actions are logged to:
```
/var/log/sys-repair.log
```

Log includes:
- Timestamps
- Operation type (INFO, SUCCESS, WARNING, ERROR)
- Commands executed
- User confirmations
- Module headers for easy navigation

Enable debug logging:
```bash
DEBUG=true sudo ./sys-repair.sh --boot
```

---

## 🎨 Terminal UI Features

- **Color-coded output** (Red = Error, Green = Success, Yellow = Warning, Blue = Info)
- **Bold headers and dividers** for visual separation
- **Interactive menus** with clear options
- **User confirmation prompts** before dangerous operations
- **Progress tracking** to avoid redundant operations

---

## 🆘 Safety Features

- ❗ **User confirmation required** before GRUB reinstall or lock removal
- 🔄 **Idempotent design** — won’t re-run completed operations in same session
- 💾 **Automatic config backup** before every modification
- 🧭 **Distribution-aware logic** — uses correct package manager and paths
- 🧯 **Error trapping and cleanup** — removes temp files on exit or interrupt

---

## 📖 Command-Line Options

```bash
sudo ./sys-repair.sh [OPTION]

OPTIONS:
    --all          Run all diagnostics and repairs interactively
    --boot         Run boot/display repair module only
    --packages     Run package manager fixes module only
    --disk         Run disk & filesystem health module only
    --logs         Extract critical system logs only
    --help, -h     Show this help message
    --version, -v  Show script version

EXAMPLES:
    sudo ./sys-repair.sh                 # Interactive menu
    sudo ./sys-repair.sh --all           # Full system check (with prompts)
    sudo ./sys-repair.sh --boot          # Fix boot issues only
    sudo ./sys-repair.sh --logs          # Just extract error logs for review
```

---

## 🧑‍💻 For Advanced Users

### Customize Behavior

Set environment variables before running:

```bash
# Enable verbose debug logging
DEBUG=true sudo ./sys-repair.sh --boot

# Change backup directory (default: /var/backup/...)
export BACKUP_DIR="/opt/backups/sys-repair-$(date +%Y%m%d_%H%M%S)"
sudo ./sys-repair.sh --all
```

### Extend Support

The script’s modular structure makes it easy to add support for:
- Other init systems (runit, s6)
- Additional package managers (apk, pkg)
- Cloud-specific diagnostics (AWS, Azure metadata checks)
- Hardware RAID or LVM diagnostics

> 💡 Contributions welcome! Fork and submit PRs.

---

## 📜 License

**MIT License** — Free to use, modify, and distribute — even commercially.

---

## 📞 Support & Feedback

Found a bug? Have a feature request?

👉 Open an issue on GitHub or contact the author:  
**Senior Linux Systems Engineer** — *Designed for production environments, tested in crisis recovery scenarios.*

---

## 🧭 Final Notes

✅ Always **reboot after major repairs** (especially GRUB or driver changes).  
✅ Review **`/var/log/sys-repair.log`** if something goes wrong.  
✅ Keep **recovery media** ready when repairing bootloaders.  
✅ Use `--logs` first to understand the problem before applying fixes.

---

> “An ounce of prevention is worth a pound of cure — but when your system breaks at 3 AM, this script is your emergency toolkit.” 💪🐧

---

📄 **Save this README alongside `sys-repair.sh` for quick reference during emergencies.**

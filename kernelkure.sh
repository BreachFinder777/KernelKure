#!/bin/bash
#===============================================================================
#
#          FILE: sys-repair.sh
#
#         USAGE: sudo ./sys-repair.sh [--all|--boot|--packages|--disk|--logs]
#
#   DESCRIPTION: Production-grade Linux system diagnostic and repair tool.
#                Designed to diagnose and repair common boot and system issues
#                across major Linux distributions.
#
#       OPTIONS:
#         --all       Run all diagnostics and repairs
#         --boot      Boot/Display repair only
#         --packages  Package manager fixes only
#         --disk      Disk & filesystem health only
#         --logs      Extract critical system logs only
#         --help      Display help message
#
#  REQUIREMENTS: Root privileges, bash 4.0+
#        AUTHOR: Senior Linux Systems Engineer
#       VERSION: 1.0.0
#       CREATED: 2024
#       LICENSE: MIT
#
#===============================================================================

set -o pipefail

#-------------------------------------------------------------------------------
# GLOBAL CONSTANTS & VARIABLES
#-------------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly BACKUP_DIR="/var/backup/sys-repair-$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="/var/log/sys-repair.log"
readonly MIN_BASH_VERSION=4

# Distribution detection variables
DISTRO=""
DISTRO_FAMILY=""
DISTRO_VERSION=""
PKG_MANAGER=""

# State tracking for idempotency
declare -A COMPLETED_OPERATIONS

# Terminal color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS
#-------------------------------------------------------------------------------
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_to_file() {
    local level="$1"
    local message="$2"
    
    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$(get_timestamp)] [$level] $message" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC}    $message"
    log_to_file "INFO" "$message"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    log_to_file "SUCCESS" "$message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    log_to_file "WARNING" "$message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC}   $message" >&2
    log_to_file "ERROR" "$message"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${DIM}[DEBUG]${NC}   $message"
        log_to_file "DEBUG" "$message"
    fi
}

log_header() {
    local title="$1"
    local width=78
    local padding=$(( (width - ${#title} - 2) / 2 ))
    
    echo ""
    echo -e "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${CYAN}${BOLD}$(printf ' %.0s' $(seq 1 $padding)) $title $(printf ' %.0s' $(seq 1 $padding))${NC}"
    echo -e "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
    log_to_file "HEADER" "=== $title ==="
}

log_subheader() {
    local title="$1"
    echo ""
    echo -e "${MAGENTA}${BOLD}─── $title ───${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------
command_exists() {
    command -v "$1" &>/dev/null
}

is_operation_completed() {
    local operation="$1"
    [[ "${COMPLETED_OPERATIONS[$operation]:-}" == "true" ]]
}

mark_operation_completed() {
    local operation="$1"
    COMPLETED_OPERATIONS[$operation]="true"
}

confirm_action() {
    local prompt="$1"
    local default="${2:-no}"
    local response
    
    echo ""
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║  CONFIRMATION REQUIRED                                           ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}$prompt${NC}"
    echo ""
    
    if [[ "$default" == "yes" ]]; then
        read -r -p "Proceed? [Y/n]: " response
        response="${response:-y}"
    else
        read -r -p "Proceed? [y/N]: " response
        response="${response:-n}"
    fi
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            log_to_file "CONFIRM" "User confirmed: $prompt"
            return 0
            ;;
        *)
            log_info "Operation cancelled by user"
            return 1
            ;;
    esac
}

backup_file() {
    local source_file="$1"
    local description="${2:-configuration file}"
    
    if [[ ! -e "$source_file" ]]; then
        log_debug "Backup skipped (file not found): $source_file"
        return 1
    fi
    
    # Create backup directory structure
    if [[ ! -d "$BACKUP_DIR" ]]; then
        if ! mkdir -p "$BACKUP_DIR"; then
            log_error "Failed to create backup directory: $BACKUP_DIR"
            return 1
        fi
        chmod 700 "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi
    
    # Preserve directory structure in backup
    local backup_subdir="${BACKUP_DIR}$(dirname "$source_file")"
    mkdir -p "$backup_subdir"
    
    local backup_path="${backup_subdir}/$(basename "$source_file")"
    
    # Handle existing backups (add timestamp suffix)
    if [[ -e "$backup_path" ]]; then
        backup_path="${backup_path}.$(date +%H%M%S)"
    fi
    
    if cp -a "$source_file" "$backup_path" 2>/dev/null; then
        log_success "Backed up $description: $source_file"
        log_debug "Backup location: $backup_path"
        return 0
    else
        log_error "Failed to backup: $source_file"
        return 1
    fi
}

restore_backup() {
    local original_file="$1"
    local backup_file="${BACKUP_DIR}${original_file}"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "No backup found for: $original_file"
        return 1
    fi
    
    if cp -a "$backup_file" "$original_file"; then
        log_success "Restored from backup: $original_file"
        return 0
    else
        log_error "Failed to restore: $original_file"
        return 1
    fi
}

check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt "$MIN_BASH_VERSION" ]]; then
        log_error "This script requires Bash version $MIN_BASH_VERSION or higher"
        log_error "Current version: ${BASH_VERSION}"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    log_debug "Cleanup called with exit code: $exit_code"
    rm -f /tmp/sys-repair-*.tmp 2>/dev/null
    exit $exit_code
}

trap cleanup EXIT INT TERM

#-------------------------------------------------------------------------------
# MODULE: ENVIRONMENT CHECKS
#-------------------------------------------------------------------------------
check_root_privileges() {
    log_info "Verifying root privileges..."
    
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo ""
        echo "Please run with: sudo $SCRIPT_NAME"
        echo "           or: su -c './$SCRIPT_NAME'"
        exit 1
    fi
    
    log_success "Running with root privileges (UID: $EUID)"
}

detect_distribution() {
    log_info "Detecting Linux distribution..."
    
    # Primary detection method: /etc/os-release
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        
        # Determine distribution family and package manager
        case "${ID,,}" in
            ubuntu|debian|linuxmint|pop|elementary|zorin|kali|raspbian|mx)
                DISTRO_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
            fedora)
                DISTRO_FAMILY="rhel"
                PKG_MANAGER="dnf"
                ;;
            rhel|centos|rocky|alma|ol|scientific)
                DISTRO_FAMILY="rhel"
                if command_exists dnf; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            arch|manjaro|endeavouros|garuda|artix)
                DISTRO_FAMILY="arch"
                PKG_MANAGER="pacman"
                ;;
            opensuse*|sles|suse)
                DISTRO_FAMILY="suse"
                PKG_MANAGER="zypper"
                ;;
            gentoo)
                DISTRO_FAMILY="gentoo"
                PKG_MANAGER="emerge"
                ;;
            void)
                DISTRO_FAMILY="void"
                PKG_MANAGER="xbps"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                if command_exists apt; then
                    PKG_MANAGER="apt"
                    DISTRO_FAMILY="debian"
                elif command_exists dnf; then
                    PKG_MANAGER="dnf"
                    DISTRO_FAMILY="rhel"
                elif command_exists yum; then
                    PKG_MANAGER="yum"
                    DISTRO_FAMILY="rhel"
                elif command_exists pacman; then
                    PKG_MANAGER="pacman"
                    DISTRO_FAMILY="arch"
                elif command_exists zypper; then
                    PKG_MANAGER="zypper"
                    DISTRO_FAMILY="suse"
                else
                    PKG_MANAGER="unknown"
                fi
                log_warning "Unknown distribution: ${ID}. Some features may not work."
                ;;
        esac
        
        log_success "Detected: ${PRETTY_NAME:-$ID} (Family: $DISTRO_FAMILY)"
        log_info "Package manager: $PKG_MANAGER"
        
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
        DISTRO_FAMILY="debian"
        PKG_MANAGER="apt"
        DISTRO_VERSION=$(cat /etc/debian_version)
        log_success "Detected: Debian $DISTRO_VERSION"
        
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="rhel"
        DISTRO_FAMILY="rhel"
        PKG_MANAGER=$(command_exists dnf && echo "dnf" || echo "yum")
        DISTRO_VERSION=$(cat /etc/redhat-release)
        log_success "Detected: $DISTRO_VERSION"
        
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
        DISTRO_FAMILY="arch"
        PKG_MANAGER="pacman"
        log_success "Detected: Arch Linux"
        
    else
        log_error "Unable to detect Linux distribution"
        log_error "This script supports: Debian/Ubuntu, RHEL/Fedora/CentOS, Arch Linux"
        exit 1
    fi
}

detect_init_system() {
    log_info "Detecting init system..."
    
    if [[ -d /run/systemd/system ]]; then
        log_success "Init system: systemd"
        echo "systemd"
    elif [[ -f /sbin/init ]] && /sbin/init --version 2>&1 | grep -q upstart; then
        log_success "Init system: upstart"
        echo "upstart"
    elif [[ -f /etc/init.d/cron ]] && [[ ! -d /run/systemd/system ]]; then
        log_success "Init system: sysvinit"
        echo "sysvinit"
    elif command_exists openrc; then
        log_success "Init system: OpenRC"
        echo "openrc"
    else
        log_warning "Init system: unknown"
        echo "unknown"
    fi
}

detect_boot_mode() {
    log_info "Detecting boot mode..."
    
    if [[ -d /sys/firmware/efi ]]; then
        log_success "Boot mode: UEFI"
        echo "uefi"
    else
        log_success "Boot mode: BIOS/Legacy"
        echo "bios"
    fi
}

initialize_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null
    fi
    
    if touch "$LOG_FILE" 2>/dev/null; then
        chmod 640 "$LOG_FILE"
        log_info "Log file initialized: $LOG_FILE"
    else
        log_warning "Cannot write to log file: $LOG_FILE"
    fi
    
    {
        echo ""
        echo "==============================================================================="
        echo "Session started: $(get_timestamp)"
        echo "Script version: $SCRIPT_VERSION"
        echo "==============================================================================="
    } >> "$LOG_FILE" 2>/dev/null
}

run_environment_checks() {
    log_header "ENVIRONMENT CHECKS"
    
    check_bash_version
    check_root_privileges
    detect_distribution
    detect_init_system > /dev/null
    detect_boot_mode > /dev/null
    initialize_logging
    
    log_subheader "System Information"
    log_info "Kernel: $(uname -r)"
    log_info "Architecture: $(uname -m)"
    log_info "Hostname: $(hostname)"
    log_info "Backup directory: $BACKUP_DIR"
    
    mark_operation_completed "environment_checks"
}

#-------------------------------------------------------------------------------
# MODULE: BOOT/DISPLAY REPAIR
#-------------------------------------------------------------------------------
detect_boot_device() {
    local boot_device=""
    local boot_partition=""
    
    log_info "Detecting boot device..."
    
    if [[ -d /sys/firmware/efi ]]; then
        boot_partition=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null | head -1)
        if [[ -z "$boot_partition" ]]; then
            boot_partition=$(findmnt -n -o SOURCE /boot 2>/dev/null | head -1)
        fi
    fi
    
    if [[ -z "$boot_partition" ]]; then
        boot_partition=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    fi
    
    if [[ -n "$boot_partition" ]]; then
        if [[ "$boot_partition" =~ ^/dev/nvme ]]; then
            boot_device=$(echo "$boot_partition" | sed 's/p[0-9]*$//')
        elif [[ "$boot_partition" =~ ^/dev/[sv]d ]]; then
            boot_device=$(echo "$boot_partition" | sed 's/[0-9]*$//')
        else
            boot_device=$(lsblk -no PKNAME "$boot_partition" 2>/dev/null | head -1)
            [[ -n "$boot_device" ]] && boot_device="/dev/$boot_device"
        fi
    fi
    
    if [[ -n "$boot_device" ]] && [[ -b "$boot_device" ]]; then
        log_info "Detected boot device: $boot_device"
        echo "$boot_device"
    else
        log_warning "Could not automatically detect boot device"
        echo ""
    fi
}

backup_grub_configuration() {
    log_info "Backing up GRUB configuration files..."
    
    local grub_files=(
        "/etc/default/grub"
        "/boot/grub/grub.cfg"
        "/boot/grub2/grub.cfg"
    )
    
    for file in "${grub_files[@]}"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "GRUB config"
        fi
    done
    
    # Backup grub.d directory
    if [[ -d /etc/grub.d ]]; then
        local backup_target="${BACKUP_DIR}/etc/grub.d"
        mkdir -p "$backup_target"
        cp -a /etc/grub.d/* "$backup_target/" 2>/dev/null
        log_success "Backed up /etc/grub.d/"
    fi
}

reinstall_grub_debian() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    
    log_info "Reinstalling GRUB for Debian-based system..."
    
    apt-get update -qq
    
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installing GRUB for UEFI..."
        
        apt-get install --reinstall -y grub-efi-amd64 grub-efi-amd64-signed shim-signed 2>&1 | while read -r line; do
            log_debug "$line"
        done
        
        local efi_dir="/boot/efi"
        if [[ ! -d "$efi_dir/EFI" ]]; then
            log_error "EFI directory not found at $efi_dir"
            return 1
        fi
        
        grub-install --target=x86_64-efi --efi-directory="$efi_dir" --bootloader-id=ubuntu --recheck 2>&1 || {
            log_error "grub-install failed"
            return 1
        }
    else
        log_info "Installing GRUB for BIOS/Legacy..."
        
        apt-get install --reinstall -y grub-pc 2>&1 | while read -r line; do
            log_debug "$line"
        done
        
        grub-install --target=i386-pc --recheck "$boot_device" 2>&1 || {
            log_error "grub-install failed"
            return 1
        }
    fi
    
    log_info "Regenerating GRUB configuration..."
    update-grub 2>&1 || {
        log_error "update-grub failed"
        return 1
    }
    
    return 0
}

reinstall_grub_rhel() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    
    log_info "Reinstalling GRUB for RHEL-based system..."
    
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installing GRUB for UEFI..."
        
        $PKG_MANAGER reinstall -y grub2-efi-x64 shim-x64 2>&1 | while read -r line; do
            log_debug "$line"
        done
        
        local efi_dir="/boot/efi"
        
        grub2-install --target=x86_64-efi --efi-directory="$efi_dir" --bootloader-id=rhel --recheck 2>&1 || {
            log_error "grub2-install failed"
            return 1
        }
    else
        log_info "Installing GRUB for BIOS/Legacy..."
        
        $PKG_MANAGER reinstall -y grub2-pc 2>&1 | while read -r line; do
            log_debug "$line"
        done
        
        grub2-install --target=i386-pc --recheck "$boot_device" 2>&1 || {
            log_error "grub2-install failed"
            return 1
        }
    fi
    
    log_info "Regenerating GRUB configuration..."
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 || {
        log_error "grub2-mkconfig failed"
        return 1
    }
    
    return 0
}

reinstall_grub_arch() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    
    log_info "Reinstalling GRUB for Arch-based system..."
    
    pacman -S --noconfirm --needed grub 2>&1 | while read -r line; do
        log_debug "$line"
    done
    
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installing GRUB for UEFI..."
        
        pacman -S --noconfirm --needed efibootmgr 2>&1
        
        local efi_dir="/boot/efi"
        [[ ! -d "$efi_dir" ]] && efi_dir="/boot"
        
        grub-install --target=x86_64-efi --efi-directory="$efi_dir" --bootloader-id=GRUB --recheck 2>&1 || {
            log_error "grub-install failed"
            return 1
        }
    else
        log_info "Installing GRUB for BIOS/Legacy..."
        
        grub-install --target=i386-pc --recheck "$boot_device" 2>&1 || {
            log_error "grub-install failed"
            return 1
        }
    fi
    
    log_info "Regenerating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || {
        log_error "grub-mkconfig failed"
        return 1
    }
    
    return 0
}

repair_grub() {
    log_subheader "GRUB Bootloader Repair"
    
    if is_operation_completed "grub_repair"; then
        log_info "GRUB repair already completed in this session"
        return 0
    fi
    
    if ! confirm_action "This will reinstall and reconfigure the GRUB bootloader.
This is a CRITICAL operation that could affect system boot.
Ensure you have a backup or recovery media available."; then
        return 1
    fi
    
    backup_grub_configuration
    
    local boot_device
    boot_device=$(detect_boot_device)
    
    if [[ -z "$boot_device" ]]; then
        log_warning "Could not automatically detect boot device"
        echo ""
        echo "Available block devices:"
        lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^NAME|disk"
        echo ""
        read -r -p "Enter boot device (e.g., /dev/sda): " boot_device
        
        if [[ ! -b "$boot_device" ]]; then
            log_error "Invalid block device: $boot_device"
            return 1
        fi
    fi
    
    log_info "Using boot device: $boot_device"
    
    local result=0
    case "$DISTRO_FAMILY" in
        debian)
            reinstall_grub_debian "$boot_device"
            result=$?
            ;;
        rhel)
            reinstall_grub_rhel "$boot_device"
            result=$?
            ;;
        arch)
            reinstall_grub_arch "$boot_device"
            result=$?
            ;;
        *)
            log_error "GRUB repair not supported for distribution: $DISTRO_FAMILY"
            return 1
            ;;
    esac
    
    if [[ $result -eq 0 ]]; then
        log_success "GRUB bootloader repair completed successfully"
        mark_operation_completed "grub_repair"
    else
        log_error "GRUB bootloader repair failed"
        log_info "You may restore from backup at: $BACKUP_DIR"
    fi
    
    return $result
}

detect_gpu_hardware() {
    log_info "Detecting GPU hardware..."
    
    local gpus
    gpus=$(lspci 2>/dev/null | grep -iE "vga|3d|display" || true)
    
    if [[ -z "$gpus" ]]; then
        log_warning "No GPU detected via lspci"
        return
    fi
    
    echo "$gpus" | while IFS= read -r line; do
        log_info "Found: $line"
    done
    
    if echo "$gpus" | grep -qi nvidia; then
        echo "nvidia"
    elif echo "$gpus" | grep -qi "amd\|ati\|radeon"; then
        echo "amd"
    elif echo "$gpus" | grep -qi intel; then
        echo "intel"
    else
        echo "unknown"
    fi
}

check_gpu_driver_conflicts() {
    log_subheader "GPU Driver Conflict Check"
    
    local conflicts_found=false
    local gpu_type
    gpu_type=$(detect_gpu_hardware)
    
    log_info "Checking loaded graphics drivers..."
    
    local nvidia_proprietary=false
    local nouveau_loaded=false
    
    if lsmod | grep -q "^nvidia "; then
        nvidia_proprietary=true
        log_info "NVIDIA proprietary driver is loaded"
    fi
    
    if lsmod | grep -q "^nvidia_drm "; then
        log_info "NVIDIA DRM module is loaded"
    fi
    
    if lsmod | grep -q "^nouveau "; then
        nouveau_loaded=true
        log_warning "Nouveau (open-source NVIDIA driver) is loaded"
    fi
    
    if $nvidia_proprietary && $nouveau_loaded; then
        log_error "CONFLICT: Both NVIDIA proprietary and Nouveau drivers are loaded!"
        conflicts_found=true
        echo ""
        echo "Suggested fixes:"
        echo "  1. Blacklist nouveau: echo 'blacklist nouveau' >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
        echo "  2. Regenerate initramfs and reboot"
    fi
    
    if lsmod | grep -q "^amdgpu "; then
        log_info "AMDGPU driver is loaded"
    fi
    
    if lsmod | grep -q "^radeon "; then
        log_info "Radeon driver is loaded"
        if lsmod | grep -q "^amdgpu "; then
            log_warning "Both amdgpu and radeon drivers are loaded (may be intentional for older cards)"
        fi
    fi
    
    if lsmod | grep -q "^i915 "; then
        log_info "Intel i915 driver is loaded"
    fi
    
    if [[ "$gpu_type" == "nvidia" ]] && ! $nvidia_proprietary && ! $nouveau_loaded; then
        log_warning "NVIDIA GPU detected but no graphics driver is loaded!"
        conflicts_found=true
    fi
    
    if [[ -f /var/log/Xorg.0.log ]]; then
        log_info "Checking Xorg log for GPU errors..."
        local xorg_errors
        xorg_errors=$(grep -iE "error|failed|fatal" /var/log/Xorg.0.log 2>/dev/null | tail -5)
        if [[ -n "$xorg_errors" ]]; then
            log_warning "Errors found in Xorg log:"
            echo "$xorg_errors" | while IFS= read -r line; do
                echo "  $line"
            done
        fi
    fi
    
    if $conflicts_found; then
        return 1
    else
        log_success "No GPU driver conflicts detected"
        return 0
    fi
}

backup_display_configs() {
    log_info "Backing up display configuration files..."
    
    local display_files=(
        "/etc/X11/xorg.conf"
        "/etc/gdm3/custom.conf"
        "/etc/gdm/custom.conf"
        "/etc/sddm.conf"
        "/etc/lightdm/lightdm.conf"
    )
    
    for file in "${display_files[@]}"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "display config"
        fi
    done
    
    # Backup X11 config directories
    local config_dirs=(
        "/etc/X11/xorg.conf.d"
        "/usr/share/X11/xorg.conf.d"
    )
    
    shopt -s nullglob
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            for conf_file in "$dir"/*.conf; do
                if [[ -f "$conf_file" ]]; then
                    backup_file "$conf_file" "X11 config"
                fi
            done
        fi
    done
    shopt -u nullglob
}

regenerate_xorg_configuration() {
    log_subheader "X11/Xorg Configuration"
    
    backup_display_configs
    
    if [[ -f /etc/X11/xorg.conf ]]; then
        log_warning "Found /etc/X11/xorg.conf - this may override auto-detection"
        if confirm_action "Would you like to disable /etc/X11/xorg.conf to allow auto-configuration?"; then
            mv /etc/X11/xorg.conf "/etc/X11/xorg.conf.disabled.$(date +%Y%m%d)"
            log_success "Moved xorg.conf to xorg.conf.disabled"
        fi
    fi
    
    if command_exists nvidia-xconfig; then
        local gpu_type
        gpu_type=$(detect_gpu_hardware)
        if [[ "$gpu_type" == "nvidia" ]]; then
            if confirm_action "NVIDIA tools detected. Generate new Xorg config with nvidia-xconfig?"; then
                nvidia-xconfig 2>&1
                log_success "Generated new Xorg configuration with nvidia-xconfig"
            fi
        fi
    fi
    
    if [[ -d /etc/X11/xorg.conf.d ]]; then
        log_info "Checking for problematic X11 configuration snippets..."
        shopt -s nullglob
        for conf_file in /etc/X11/xorg.conf.d/*.conf; do
            if [[ -f "$conf_file" ]]; then
                if grep -q "nvidia" "$conf_file" && ! lsmod | grep -q "^nvidia "; then
                    log_warning "Config references nvidia but driver not loaded: $conf_file"
                fi
                if grep -q "nouveau" "$conf_file" && ! lsmod | grep -q "^nouveau "; then
                    log_warning "Config references nouveau but driver not loaded: $conf_file"
                fi
            fi
        done
        shopt -u nullglob
    fi
    
    log_success "X11 configuration check completed"
}

check_wayland_configuration() {
    log_subheader "Wayland Configuration"
    
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        log_info "Current session is using Wayland"
    elif [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
        log_info "Current session is using X11"
    else
        log_info "Session type: ${XDG_SESSION_TYPE:-not detected}"
    fi
    
    local gdm_config=""
    if [[ -f /etc/gdm3/custom.conf ]]; then
        gdm_config="/etc/gdm3/custom.conf"
    elif [[ -f /etc/gdm/custom.conf ]]; then
        gdm_config="/etc/gdm/custom.conf"
    fi
    
    if [[ -n "$gdm_config" ]]; then
        backup_file "$gdm_config" "GDM config"
        
        if grep -q "^WaylandEnable=false" "$gdm_config"; then
            log_info "Wayland is disabled in GDM configuration"
            if confirm_action "Would you like to re-enable Wayland in GDM?"; then
                sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' "$gdm_config"
                log_success "Wayland re-enabled in GDM (requires restart)"
            fi
        elif grep -q "^#WaylandEnable=false" "$gdm_config" || ! grep -q "WaylandEnable" "$gdm_config"; then
            log_info "Wayland is enabled in GDM configuration"
        fi
    fi
    
    if lsmod | grep -q "^nvidia "; then
        if lsmod | grep -q "^nvidia_drm "; then
            log_info "NVIDIA DRM module loaded - Wayland may work with recent drivers"
            local modeset_enabled
            modeset_enabled=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "N")
            if [[ "$modeset_enabled" != "Y" ]]; then
                log_warning "NVIDIA DRM modesetting not enabled"
                echo "  To enable, add 'nvidia-drm.modeset=1' to kernel parameters"
            else
                log_success "NVIDIA DRM modesetting is enabled"
            fi
        else
            log_warning "NVIDIA DRM module not loaded - Wayland support limited"
        fi
    fi
    
    log_success "Wayland configuration check completed"
}

check_kernel_graphics_parameters() {
    log_subheader "Kernel Graphics Parameters"
    
    if [[ -f /etc/default/grub ]]; then
        local grub_cmdline
        grub_cmdline=$(grep "^GRUB_CMDLINE_LINUX" /etc/default/grub)
        
        log_info "Current kernel parameters:"
        echo "  $grub_cmdline"
        echo ""
        
        if echo "$grub_cmdline" | grep -q "nomodeset"; then
            log_warning "'nomodeset' is set - this disables kernel mode setting"
            echo "  This may cause issues with modern GPUs and Wayland"
            echo "  Consider removing unless specifically needed for troubleshooting"
        fi
        
        if echo "$grub_cmdline" | grep -q "vga="; then
            log_warning "'vga=' parameter found - this is deprecated"
            echo "  Consider using modern framebuffer settings instead"
        fi
        
        if lsmod | grep -q "^nvidia "; then
            if ! echo "$grub_cmdline" | grep -q "nvidia-drm.modeset=1"; then
                log_info "Suggestion: Add 'nvidia-drm.modeset=1' for better Wayland/DRM support"
            fi
        fi
    fi
}

fix_black_screen() {
    log_subheader "Black Screen Diagnostics & Fixes"
    
    log_info "Running black screen diagnostic checks..."
    
    check_gpu_driver_conflicts
    
    log_info "Checking display manager status..."
    
    local active_dm=""
    for dm in gdm gdm3 sddm lightdm lxdm xdm; do
        if systemctl is-active --quiet "$dm" 2>/dev/null; then
            active_dm="$dm"
            break
        fi
    done
    
    if [[ -n "$active_dm" ]]; then
        log_success "Active display manager: $active_dm"
        local dm_errors
        dm_errors=$(journalctl -u "$active_dm" -p err -n 10 --no-pager 2>/dev/null)
        if [[ -n "$dm_errors" ]]; then
            log_warning "Recent errors from $active_dm:"
            echo "$dm_errors" | head -5
        fi
    else
        log_warning "No active display manager detected"
        for dm in gdm gdm3 sddm lightdm lxdm; do
            if systemctl list-unit-files 2>/dev/null | grep -q "^$dm"; then
                log_info "Found installed but inactive: $dm"
            fi
        done
    fi
    
    check_kernel_graphics_parameters
    
    if confirm_action "Would you like to audit and regenerate display configurations?"; then
        regenerate_xorg_configuration
        check_wayland_configuration
    fi
    
    echo ""
    log_info "Common black screen fixes to try:"
    echo "  1. Boot with 'nomodeset' kernel parameter (temporary fix)"
    echo "  2. Switch to a different TTY with Ctrl+Alt+F2"
    echo "  3. Reinstall display drivers"
    echo "  4. Check /var/log/Xorg.0.log for errors"
    echo "  5. Verify display cable connection"
    echo ""
    
    log_success "Black screen diagnostic completed"
}

run_boot_display_repair() {
    log_header "BOOT/DISPLAY REPAIR"
    
    echo "Select repair option:"
    echo "  1) Repair GRUB bootloader"
    echo "  2) Fix black screen / display issues"
    echo "  3) Check GPU driver conflicts only"
    echo "  4) All of the above"
    echo "  5) Skip this module"
    echo ""
    
    read -r -p "Enter choice [1-5]: " choice
    
    case "$choice" in
        1)
            repair_grub
            ;;
        2)
            fix_black_screen
            ;;
        3)
            check_gpu_driver_conflicts
            ;;
        4)
            repair_grub
            check_gpu_driver_conflicts
            fix_black_screen
            ;;
        5)
            log_info "Skipping boot/display repair"
            ;;
        *)
            log_warning "Invalid choice - skipping boot/display repair"
            ;;
    esac
    
    mark_operation_completed "boot_display"
}

#-------------------------------------------------------------------------------
# MODULE: PACKAGE MANAGER FIXES
#-------------------------------------------------------------------------------
clear_apt_locks() {
    log_subheader "APT/DPKG Lock Cleanup"
    
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/lib/apt/lists/lock"
        "/var/cache/apt/archives/lock"
    )
    
    local locks_in_use=false
    local stale_locks=()
    
    for lock_file in "${lock_files[@]}"; do
        if [[ -f "$lock_file" ]]; then
            if fuser "$lock_file" &>/dev/null; then
                log_warning "Lock file in active use: $lock_file"
                locks_in_use=true
            else
                stale_locks+=("$lock_file")
                log_info "Stale lock found: $lock_file"
            fi
        fi
    done
    
    if [[ -f /var/lib/dpkg/status-old ]]; then
        log_info "Found dpkg status backup (may indicate interrupted operation)"
    fi
    
    if $locks_in_use; then
        log_warning "Some lock files are in active use by other processes"
        log_info "Processes using package manager:"
        pgrep -a "apt|dpkg" 2>/dev/null || echo "  (none found)"
        
        if confirm_action "Would you like to terminate these processes and clear locks?"; then
            killall -9 apt apt-get dpkg 2>/dev/null || true
            sleep 2
        else
            log_info "Skipping active lock cleanup"
            return 1
        fi
    fi
    
    if [[ ${#stale_locks[@]} -gt 0 ]] || $locks_in_use; then
        if confirm_action "Clear stale package manager locks?"; then
            for lock_file in "${lock_files[@]}"; do
                if [[ -f "$lock_file" ]]; then
                    rm -f "$lock_file"
                    log_success "Removed: $lock_file"
                fi
            done
            
            log_info "Reconfiguring dpkg..."
            dpkg --configure -a 2>&1 | while read -r line; do
                log_debug "$line"
            done
            
            log_success "APT/DPKG locks cleared"
        fi
    else
        log_success "No package manager locks detected"
    fi
}

clear_rpm_locks() {
    log_subheader "RPM/DNF/YUM Lock Cleanup"
    
    local lock_files=(
        "/var/run/yum.pid"
        "/var/run/dnf.pid"
        "/var/lib/rpm/.rpm.lock"
    )
    
    local locks_found=false
    
    for lock_file in "${lock_files[@]}"; do
        if [[ -e "$lock_file" ]]; then
            locks_found=true
            log_info "Found: $lock_file"
        fi
    done
    
    # Check for RPM DB locks
    if ls /var/lib/rpm/__db.* &>/dev/null; then
        locks_found=true
        log_info "Found RPM database lock files"
    fi
    
    if $locks_found; then
        if confirm_action "Clear package manager locks and rebuild RPM database?"; then
            killall -9 yum dnf rpm 2>/dev/null || true
            sleep 2
            
            rm -f /var/run/yum.pid /var/run/dnf.pid 2>/dev/null
            rm -f /var/lib/rpm/.rpm.lock 2>/dev/null
            rm -f /var/lib/rpm/__db.* 2>/dev/null
            
            log_info "Rebuilding RPM database..."
            
            if [[ -d /var/lib/rpm ]]; then
                mkdir -p "$BACKUP_DIR"
                cp -a /var/lib/rpm "$BACKUP_DIR/rpm_db_backup" 2>/dev/null
            fi
            
            rpm --rebuilddb 2>&1 | while read -r line; do
                log_debug "$line"
            done
            
            log_success "RPM locks cleared and database rebuilt"
        fi
    else
        log_success "No RPM locks detected"
    fi
}

clear_pacman_locks() {
    log_subheader "Pacman Lock Cleanup"
    
    local lock_file="/var/lib/pacman/db.lck"
    
    if [[ -f "$lock_file" ]]; then
        log_warning "Pacman database lock found: $lock_file"
        
        if pgrep -x pacman > /dev/null; then
            log_warning "Pacman process is currently running"
            if confirm_action "Terminate pacman and remove lock?"; then
                killall -9 pacman 2>/dev/null
                sleep 1
                rm -f "$lock_file"
                log_success "Pacman lock removed"
            fi
        else
            if confirm_action "Remove stale pacman lock file?"; then
                rm -f "$lock_file"
                log_success "Pacman lock removed"
            fi
        fi
    else
        log_success "No pacman locks detected"
    fi
}

repair_apt_packages() {
    log_subheader "APT Package Repair"
    
    log_info "Updating package cache..."
    apt-get update 2>&1 | tail -5
    
    log_info "Fixing broken dependencies..."
    apt-get --fix-broken install -y 2>&1 | while read -r line; do
        log_debug "$line"
    done
    
    log_info "Reconfiguring packages..."
    dpkg --configure -a 2>&1 | while read -r line; do
        log_debug "$line"
    done
    
    if confirm_action "Remove unused packages (autoremove)?"; then
        apt-get autoremove -y 2>&1 | tail -5
    fi
    
    log_info "Cleaning package cache..."
    apt-get autoclean 2>&1 > /dev/null
    
    log_success "APT package repair completed"
}

repair_rpm_packages() {
    log_subheader "RPM Package Repair"
    
    log_info "Cleaning package cache..."
    $PKG_MANAGER clean all 2>&1 > /dev/null
    
    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        log_info "Running distro-sync..."
        dnf distro-sync -y 2>&1 | tail -10
        
        log_info "Checking for broken dependencies..."
        dnf check 2>&1 | head -20
    else
        log_info "Checking for package problems..."
        yum check 2>&1 | head -20
        
        if command_exists package-cleanup; then
            package-cleanup --problems 2>&1 | head -20
        fi
    fi
    
    log_success "RPM package repair completed"
}

repair_pacman_packages() {
    log_subheader "Pacman Package Repair"
    
    log_info "Synchronizing package databases..."
    pacman -Sy 2>&1 | tail -5
    
    log_info "Checking for orphaned packages..."
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null || true)
    
    if [[ -n "$orphans" ]]; then
        echo "Orphaned packages found:"
        echo "$orphans" | head -10
        
        if confirm_action "Remove orphaned packages?"; then
            # shellcheck disable=SC2046
            pacman -Rns --noconfirm $(pacman -Qtdq) 2>&1 | tail -5
        fi
    else
        log_info "No orphaned packages found"
    fi
    
    log_info "Checking package integrity..."
    pacman -Qk 2>&1 | grep -v "0 missing files" | head -10 || log_success "All packages intact"
    
    log_success "Pacman package repair completed"
}

run_package_manager_fixes() {
    log_header "PACKAGE MANAGER FIXES"
    
    case "$DISTRO_FAMILY" in
        debian)
            clear_apt_locks
            ;;
        rhel)
            clear_rpm_locks
            ;;
        arch)
            clear_pacman_locks
            ;;
        suse)
            log_info "Checking for zypper locks..."
            if [[ -f /var/run/zypp.pid ]]; then
                if confirm_action "Remove zypper lock?"; then
                    rm -f /var/run/zypp.pid
                    log_success "Zypper lock removed"
                fi
            else
                log_success "No zypper locks detected"
            fi
            ;;
        *)
            log_warning "Lock cleanup not implemented for: $DISTRO_FAMILY"
            ;;
    esac
    
    if confirm_action "Repair broken package dependencies?"; then
        case "$DISTRO_FAMILY" in
            debian)
                repair_apt_packages
                ;;
            rhel)
                repair_rpm_packages
                ;;
            arch)
                repair_pacman_packages
                ;;
            *)
                log_warning "Package repair not implemented for: $DISTRO_FAMILY"
                ;;
        esac
    fi
    
    mark_operation_completed "package_fixes"
}

#-------------------------------------------------------------------------------
# MODULE: DISK & FILESYSTEM HEALTH
#-------------------------------------------------------------------------------
check_disk_space() {
    log_subheader "Disk Space Analysis"
    
    echo "Filesystem usage:"
    echo ""
    df -hT | grep -vE "^tmpfs|^devtmpfs|^overlay|^shm" | head -20
    echo ""
    
    local critical_found=false
    local warning_found=false
    
    while IFS= read -r line; do
        local usage mount_point
        usage=$(echo "$line" | awk '{print $(NF-1)}' | tr -d '%')
        mount_point=$(echo "$line" | awk '{print $NF}')
        
        [[ ! "$usage" =~ ^[0-9]+$ ]] && continue
        
        if [[ $usage -ge 95 ]]; then
            log_error "CRITICAL: $mount_point is at ${usage}%"
            critical_found=true
        elif [[ $usage -ge 90 ]]; then
            log_error "DANGER: $mount_point is at ${usage}%"
            critical_found=true
        elif [[ $usage -ge 80 ]]; then
            log_warning "WARNING: $mount_point is at ${usage}%"
            warning_found=true
        fi
    done < <(df -h | grep "^/dev")
    
    if $critical_found; then
        echo ""
        log_info "Disk cleanup suggestions:"
        
        case "$DISTRO_FAMILY" in
            debian)
                echo "  sudo apt-get autoremove --purge"
                echo "  sudo apt-get autoclean"
                echo "  sudo journalctl --vacuum-size=100M"
                ;;
            rhel)
                echo "  sudo $PKG_MANAGER autoremove"
                echo "  sudo $PKG_MANAGER clean all"
                echo "  sudo journalctl --vacuum-size=100M"
                ;;
            arch)
                echo "  sudo pacman -Sc"
                echo "  sudo paccache -r"
                echo "  sudo journalctl --vacuum-size=100M"
                ;;
            *)
                echo "  Check your package manager for cleanup options"
                ;;
        esac
        
        echo "  Find large files: sudo find / -xdev -size +100M -exec ls -lh {} \\; 2>/dev/null"
    elif ! $warning_found; then
        log_success "All filesystems have adequate free space"
    fi
    
    log_info "Checking inode usage..."
    
    while IFS= read -r line; do
        local inode_usage mount_point
        inode_usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount_point=$(echo "$line" | awk '{print $6}')
        
        [[ ! "$inode_usage" =~ ^[0-9]+$ ]] && continue
        
        if [[ $inode_usage -ge 90 ]]; then
            log_error "Inode usage critical on $mount_point: ${inode_usage}%"
        fi
    done < <(df -i | grep "^/dev")
}

verify_fstab() {
    log_subheader "/etc/fstab Verification"
    
    if [[ ! -f /etc/fstab ]]; then
        log_error "/etc/fstab not found!"
        return 1
    fi
    
    backup_file "/etc/fstab" "fstab"
    
    local issues_found=false
    local line_num=0
    
    log_info "Checking fstab entries..."
    
    while IFS= read -r line; do
        ((line_num++))
        
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        local device mount_point fs_type field_count
        device=$(echo "$line" | awk '{print $1}')
        mount_point=$(echo "$line" | awk '{print $2}')
        fs_type=$(echo "$line" | awk '{print $3}')
        field_count=$(echo "$line" | awk '{print NF}')
        
        if [[ $field_count -lt 4 ]]; then
            log_warning "Line $line_num: Insufficient fields ($field_count)"
            issues_found=true
            continue
        fi
        
        if [[ "$device" =~ ^UUID= ]]; then
            local uuid="${device#UUID=}"
            if ! blkid -U "$uuid" &>/dev/null; then
                log_warning "Line $line_num: UUID not found: $uuid"
                issues_found=true
            fi
        elif [[ "$device" =~ ^/dev/ ]] && [[ ! -e "$device" ]]; then
            log_warning "Line $line_num: Device not found: $device"
            issues_found=true
        fi
        
        if [[ "$mount_point" != "none" ]] && [[ "$mount_point" != "swap" ]]; then
            if [[ ! -d "$mount_point" ]]; then
                log_warning "Line $line_num: Mount point missing: $mount_point"
                issues_found=true
            fi
        fi
        
    done < /etc/fstab
    
    if command_exists findmnt; then
        log_info "Running findmnt verification..."
        local verify_output
        verify_output=$(findmnt --verify --tab-file /etc/fstab 2>&1)
        
        if [[ -n "$verify_output" ]]; then
            log_warning "findmnt verification output:"
            echo "$verify_output" | head -10
            issues_found=true
        fi
    fi
    
    if ! $issues_found; then
        log_success "/etc/fstab verification passed"
    fi
}

run_filesystem_check() {
    log_subheader "Filesystem Check (fsck)"
    
    log_info "Identifying partitions available for fsck..."
    
    echo ""
    echo "Block device overview:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | head -25
    echo ""
    
    log_info "Checking kernel messages for filesystem errors..."
    
    local fs_errors
    fs_errors=$(dmesg 2>/dev/null | grep -iE "ext[234].*error|filesystem.*error|I/O error|corruption" | tail -5)
    
    if [[ -n "$fs_errors" ]]; then
        log_warning "Filesystem errors found in kernel messages:"
        echo "$fs_errors"
    fi
    
    log_info "Looking for unmounted partitions..."
    
    local unmounted_parts=()
    
    while IFS= read -r line; do
        local name fstype mountpoint
        name=$(echo "$line" | awk '{print $1}')
        fstype=$(echo "$line" | awk '{print $2}')
        mountpoint=$(echo "$line" | awk '{print $3}')
        
        [[ -z "$fstype" ]] && continue
        [[ -n "$mountpoint" ]] && continue
        [[ "$fstype" == "swap" ]] && continue
        [[ "$fstype" == "crypto_LUKS" ]] && continue
        
        unmounted_parts+=("/dev/$name")
    done < <(lsblk -nlo NAME,FSTYPE,MOUNTPOINT 2>/dev/null)
    
    if [[ ${#unmounted_parts[@]} -gt 0 ]]; then
        echo ""
        echo "Unmounted partitions available for fsck:"
        printf '  %s\n' "${unmounted_parts[@]}"
        echo ""
        
        if confirm_action "Run fsck on unmounted partitions?"; then
            for partition in "${unmounted_parts[@]}"; do
                if [[ -b "$partition" ]]; then
                    log_info "Running fsck on $partition..."
                    
                    fsck -y "$partition" 2>&1 | while IFS= read -r line; do
                        echo "  $line"
                    done
                    
                    local fsck_status=${PIPESTATUS[0]}
                    
                    case $fsck_status in
                        0)
                            log_success "fsck completed: $partition (no errors)"
                            ;;
                        1)
                            log_success "fsck completed: $partition (errors corrected)"
                            ;;
                        2)
                            log_warning "fsck: $partition - reboot required"
                            ;;
                        4)
                            log_error "fsck: $partition - uncorrected errors"
                            ;;
                        8)
                            log_error "fsck: $partition - operational error"
                            ;;
                        *)
                            log_warning "fsck: $partition - exit code $fsck_status"
                            ;;
                    esac
                fi
            done
        fi
    else
        log_info "No unmounted partitions found for fsck"
    fi
    
    log_info "Checking root filesystem mount status..."
    
    local root_mount
    root_mount=$(mount | grep " / " | head -1)
    
    if echo "$root_mount" | grep -qE "\bro\b"; then
        log_error "Root filesystem is mounted READ-ONLY!"
        echo "  This typically indicates filesystem errors"
        echo "  To fix: fsck -y /dev/root-device (from recovery mode)"
        echo "  To remount: mount -o remount,rw /"
    else
        log_success "Root filesystem is mounted read-write"
    fi
}

run_disk_filesystem_health() {
    log_header "DISK & FILESYSTEM HEALTH"
    
    check_disk_space
    verify_fstab
    run_filesystem_check
    
    mark_operation_completed "disk_health"
}

#-------------------------------------------------------------------------------
# MODULE: SYSTEM LOG EXTRACTION
#-------------------------------------------------------------------------------
extract_critical_logs() {
    log_header "CRITICAL SYSTEM LOGS"
    
    if ! command_exists journalctl; then
        log_warning "journalctl not available - falling back to traditional logs"
        extract_traditional_logs
        return
    fi
    
    log_info "Extracting critical errors from system journal..."
    
    echo ""
    echo -e "${BOLD}Last 50 critical/error messages from current boot:${NC}"
    echo "$(printf '─%.0s' {1..78})"
    echo ""
    
    local journal_output
    journal_output=$(journalctl -p 3 -xb --no-pager -n 50 2>/dev/null)
    
    if [[ -n "$journal_output" ]]; then
        echo "$journal_output"
    else
        log_info "No critical errors found in current boot journal"
    fi
    
    echo ""
    echo "$(printf '─%.0s' {1..78})"
    
    local log_extract="/tmp/sys-repair-critical-$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "System Repair - Critical Log Extract"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo ""
        echo "$(printf '=%.0s' {1..78})"
        echo ""
        journalctl -p 3 -xb --no-pager 2>/dev/null
    } > "$log_extract"
    
    log_success "Full critical log saved to: $log_extract"
    
    log_subheader "Error Summary by Service"
    
    journalctl -p 3 -xb --no-pager -o json 2>/dev/null | \
        grep -oP '"_SYSTEMD_UNIT":"[^"]*"' 2>/dev/null | \
        sed 's/"_SYSTEMD_UNIT":"//g; s/"//g' | \
        sort | uniq -c | sort -rn | head -10 | \
        while read -r count unit; do
            printf "  %4d errors - %s\n" "$count" "$unit"
        done
    
    log_subheader "Kernel Issues Check"
    
    local kernel_issues
    kernel_issues=$(dmesg 2>/dev/null | grep -iE "panic|oops|bug:|segfault|general protection" | tail -10)
    
    if [[ -n "$kernel_issues" ]]; then
        log_error "Kernel issues detected:"
        echo "$kernel_issues"
    else
        log_success "No kernel panics or oops detected in current session"
    fi
    
    log_subheader "Out of Memory Events"
    
    local oom_events
    oom_events=$(journalctl -k -b --no-pager 2>/dev/null | grep -i "out of memory\|oom\|killed process" | tail -5)
    
    if [[ -n "$oom_events" ]]; then
        log_warning "OOM (Out of Memory) events detected:"
        echo "$oom_events"
    else
        log_success "No OOM events in current boot"
    fi
    
    log_subheader "Failed Systemd Services"
    
    local failed_services
    failed_services=$(systemctl --failed --no-pager 2>/dev/null)
    
    if echo "$failed_services" | grep -q "failed"; then
        log_warning "Failed services detected:"
        echo "$failed_services" | head -15
    else
        log_success "No failed systemd services"
    fi
    
    mark_operation_completed "log_extraction"
}

extract_traditional_logs() {
    log_info "Extracting from traditional log files..."
    
    local log_files=(
        "/var/log/syslog"
        "/var/log/messages"
        "/var/log/kern.log"
        "/var/log/boot.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -r "$log_file" ]]; then
            echo ""
            echo "=== $log_file (errors) ==="
            grep -iE "error|fail|critical|panic" "$log_file" 2>/dev/null | tail -20
        fi
    done
    
    echo ""
    echo "=== dmesg (errors) ==="
    dmesg 2>/dev/null | grep -iE "error|fail|panic" | tail -20
}

#-------------------------------------------------------------------------------
# MAIN MENU AND EXECUTION
#-------------------------------------------------------------------------------
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'BANNER'
   ███████╗██╗   ██╗███████╗      ██████╗ ███████╗██████╗  █████╗ ██╗██████╗ 
   ██╔════╝╚██╗ ██╔╝██╔════╝      ██╔══██╗██╔════╝██╔══██╗██╔══██╗██║██╔══██╗
   ███████╗ ╚████╔╝ ███████╗█████╗██████╔╝█████╗  ██████╔╝███████║██║██████╔╝
   ╚════██║  ╚██╔╝  ╚════██║╚════╝██╔══██╗██╔══╝  ██╔═══╝ ██╔══██║██║██╔══██╗
   ███████║   ██║   ███████║      ██║  ██║███████╗██║     ██║  ██║██║██║  ██║
   ╚══════╝   ╚═╝   ╚══════╝      ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
BANNER
    echo -e "${NC}"
    echo -e "${WHITE}   Linux System Diagnostic & Repair Tool${NC}"
    echo -e "${DIM}   Version $SCRIPT_VERSION | Production Grade${NC}"
    echo ""
}

show_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                           MAIN MENU                                    ║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  1)  Run All Diagnostics & Repairs (Interactive)                      ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  2)  Boot/Display Repair Module                                       ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  3)  Package Manager Fixes Module                                     ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  4)  Disk & Filesystem Health Module                                  ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  5)  Extract Critical System Logs                                     ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  6)  Show Backup Directory                                            ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  7)  Exit                                                             ${BOLD}║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    cat << HELP
Usage: $SCRIPT_NAME [OPTION]

Linux System Diagnostic & Repair Tool - Version $SCRIPT_VERSION

OPTIONS:
    --all           Run all diagnostics and repairs interactively
    --boot          Run boot/display repair module only
    --packages      Run package manager fixes module only
    --disk          Run disk & filesystem health module only
    --logs          Extract critical system logs only
    --help, -h      Display this help message
    --version, -v   Display version information

EXAMPLES:
    sudo $SCRIPT_NAME                  # Interactive menu
    sudo $SCRIPT_NAME --all            # Run all modules
    sudo $SCRIPT_NAME --boot           # Fix boot/display issues
    sudo $SCRIPT_NAME --packages       # Fix package manager issues
    sudo $SCRIPT_NAME --disk           # Check disk health
    sudo $SCRIPT_NAME --logs           # Extract error logs

NOTES:
    - This script must be run as root (sudo)
    - Backups are created before any modifications
    - Supports Debian/Ubuntu, RHEL/Fedora/CentOS, and Arch Linux

BACKUP LOCATION:
    $BACKUP_DIR

LOG FILE:
    $LOG_FILE

HELP
}

run_all_modules() {
    run_boot_display_repair
    run_package_manager_fixes
    run_disk_filesystem_health
    extract_critical_logs
    
    log_header "REPAIR SESSION COMPLETE"
    
    echo ""
    log_success "All diagnostic and repair operations completed"
    echo ""
    log_info "Session Summary:"
    echo "  • Backup directory: $BACKUP_DIR"
    echo "  • Log file: $LOG_FILE"
    echo "  • Distribution: $DISTRO ($DISTRO_FAMILY)"
    echo ""
    log_warning "A system reboot is recommended to apply all changes"
    echo ""
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "$SCRIPT_NAME version $SCRIPT_VERSION"
            exit 0
            ;;
        --all)
            show_banner
            run_environment_checks
            run_all_modules
            exit $?
            ;;
        --boot)
            show_banner
            run_environment_checks
            run_boot_display_repair
            exit $?
            ;;
        --packages)
            show_banner
            run_environment_checks
            run_package_manager_fixes
            exit $?
            ;;
        --disk)
            show_banner
            run_environment_checks
            run_disk_filesystem_health
            exit $?
            ;;
        --logs)
            show_banner
            run_environment_checks
            extract_critical_logs
            exit $?
            ;;
        "")
            show_banner
            run_environment_checks
            
            while true; do
                show_menu
                read -r -p "Enter your choice [1-7]: " menu_choice
                
                case "$menu_choice" in
                    1)
                        run_all_modules
                        ;;
                    2)
                        run_boot_display_repair
                        ;;
                    3)
                        run_package_manager_fixes
                        ;;
                    4)
                        run_disk_filesystem_health
                        ;;
                    5)
                        extract_critical_logs
                        ;;
                    6)
                        echo ""
                        log_info "Backup directory: $BACKUP_DIR"
                        if [[ -d "$BACKUP_DIR" ]]; then
                            echo "Contents:"
                            find "$BACKUP_DIR" -type f 2>/dev/null | head -20
                        else
                            echo "  (No backups created yet)"
                        fi
                        ;;
                    7)
                        echo ""
                        log_info "Exiting. Goodbye!"
                        echo ""
                        exit 0
                        ;;
                    *)
                        log_warning "Invalid choice. Please enter 1-7."
                        ;;
                esac
                
                echo ""
                read -r -p "Press Enter to continue..."
            done
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"

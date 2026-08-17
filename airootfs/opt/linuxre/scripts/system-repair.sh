#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/common.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/target.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/chroot.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/repair.sh

# ==================================================
# Requirements
# ==================================================

require_root || exit 1

require_commands \
    lsblk \
    blkid \
    mount \
    umount \
    mountpoint \
    awk \
    sed \
    arch-chroot \
    || exit 1

trap cleanup EXIT

# ==================================================
# Header
# ==================================================

clear

echo "╔══════════════════════════════════════════╗"
echo "║       LinuxRE System Repair (Arch)       ║"
echo "╚══════════════════════════════════════════╝"
echo

# ==================================================
# Detect target
# ==================================================

log "Scanning for Arch Linux installations..."
echo

if ! detect_root_filesystems; then
    die "No supported Linux root filesystems were found."
    exit 1
fi

echo "Detected filesystems:"
echo

for i in "${!ROOTS[@]}"; do
    dev="${ROOTS[$i]}"

    echo "[$((i + 1))] $dev"

    lsblk -no \
        SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS \
        "$dev" |
        sed 's/^/    /'

    echo
done

# ==================================================
# Root selection
# ==================================================

while true; do
    read -rp \
        "Select Arch Linux root filesystem [1-${#ROOTS[@]}]: " \
        choice

    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
        break
    fi

    echo "Invalid selection."
done

ROOT_DEV="${ROOTS[$((choice - 1))]}"

if ! set_root "$ROOT_DEV"; then
    die "Unable to determine root filesystem."
    exit 1
fi

# ==================================================
# Btrfs
# ==================================================

if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    if ! detect_btrfs_subvolume; then
        die "Unable to locate the Arch root subvolume."
        exit 1
    fi
fi

# ==================================================
# Prepare target
# ==================================================

echo
log "Preparing target system..."

if ! prepare_target; then
    die "Failed to prepare target system."
    exit 1
fi

echo
ok "Target system is ready."

# ==================================================
# Target summary
# ==================================================

show_target() {
    echo
    echo "========================================"
    echo "             Target Summary"
    echo "========================================"
    echo
    echo "Root:"
    echo "  Device      : $ROOT_DEV"
    echo "  UUID        : $ROOT_UUID"
    echo "  Filesystem  : $ROOT_FSTYPE"

    if [[ -n "$ROOT_SUBVOL" ]]; then
        echo "  Subvolume   : $ROOT_SUBVOL"
    fi

    echo
    echo "EFI:"
    echo "  Device      : $ESP_DEV"
    echo "  UUID        : ${ESP_UUID:-Unknown}"
    echo "  Filesystem  : $ESP_FSTYPE"
    echo "  Mount point : $ESP_MOUNT"
    echo
}

show_target

# ==================================================
# Diagnosis
# ==================================================

diagnose() {
    local failed=0

    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║            Arch Linux Diagnosis          ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    show_target

    echo "Checks:"
    echo

    verify_target || failed=1
    verify_pacman || failed=1
    verify_kernel || failed=1
    verify_initramfs || failed=1
    verify_systemd || failed=1
    verify_systemd_boot || failed=1

    echo
    echo "────────────────────────────────────────────"

    if (( failed == 0 )); then
        ok "No obvious boot/system problems detected."
    else
        warn "One or more checks failed."
    fi

    echo
    read -rp "Press Enter to return to the menu..."
}

# ==================================================
# Automatic repair
# ==================================================

automatic_repair() {
    local repair_failed=0
    local final_failed=0

    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║          LinuxRE Automatic Repair        ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    show_target

    echo "Automatic repair will:"
    echo
    echo "  • Diagnose the target system"
    echo "  • Repair only failed components"
    echo "  • Run a final diagnosis"
    echo

    read -rp "Continue? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo
        echo "Cancelled."
        read -rp "Press Enter..."
        return 0
    fi

    echo
    echo "========================================"
    echo "          Initial Diagnosis"
    echo "========================================"
    echo

    # --------------------------------------------------
    # Kernel
    # --------------------------------------------------

    if ! verify_kernel >/dev/null 2>&1; then
        log "Kernel check failed. Repairing kernel..."
        if ! repair_kernel; then
            repair_failed=1
        fi
    else
        ok "Kernel check passed. No kernel repair needed."
    fi

    # --------------------------------------------------
    # Initramfs / UKI
    # --------------------------------------------------

    if ! verify_initramfs >/dev/null 2>&1; then
        log "Initramfs / UKI check failed. Repairing..."
        if ! repair_initramfs; then
            repair_failed=1
        fi
    else
        ok "Initramfs / UKI check passed. No repair needed."
    fi

    # --------------------------------------------------
    # systemd
    # --------------------------------------------------

    if ! verify_systemd >/dev/null 2>&1; then
        log "systemd check failed. Repairing systemd..."
        if ! repair_systemd; then
            repair_failed=1
        fi
    else
        ok "systemd check passed. No systemd repair needed."
    fi

    # --------------------------------------------------
    # systemd-boot
    # --------------------------------------------------

    if ! verify_systemd_boot >/dev/null 2>&1; then
        log "systemd-boot check failed. Repairing systemd-boot..."
        if ! repair_systemd_boot; then
            repair_failed=1
        fi
    else
        ok "systemd-boot check passed. No repair needed."
    fi

    # --------------------------------------------------
    # Final diagnosis
    # --------------------------------------------------

    echo
    echo "========================================"
    echo "          Final Diagnosis"
    echo "========================================"
    echo

    verify_target || final_failed=1
    verify_pacman || final_failed=1
    verify_kernel || final_failed=1
    verify_initramfs || final_failed=1
    verify_systemd || final_failed=1
    verify_systemd_boot || final_failed=1

    echo
    echo "────────────────────────────────────────────"

    if (( repair_failed == 0 && final_failed == 0 )); then
        ok "Automatic repair completed successfully."
    else
        warn "Automatic repair completed with errors."
    fi

    echo
    read -rp "Press Enter to return to the menu..."

    (( repair_failed == 0 && final_failed == 0 ))
}

# ==================================================
# Main menu
# ==================================================

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║       LinuxRE System Repair (Arch)       ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    echo "Target:"
    echo "  Root : $ROOT_DEV"
    echo "  FS   : $ROOT_FSTYPE"

    [[ -n "$ROOT_SUBVOL" ]] &&
        echo "  Subvol: $ROOT_SUBVOL"

    echo "  ESP  : $ESP_DEV"
    echo "  Mount: $ESP_MOUNT"

    echo
    echo "────────────────────────────────────────────"
    echo
    echo "  1) Diagnose system"
    echo "  2) Repair kernel"
    echo "  3) Repair initramfs / UKI"
    echo "  4) Repair systemd"
    echo "  5) Repair systemd-boot"
    echo "  6) Automatic repair"
    echo "  7) Exit"
    echo
    echo "────────────────────────────────────────────"
    echo

    read -rp "Select an option [1-7]: " option

    case "$option" in
        1)
            diagnose
            ;;

        2)
            repair_kernel
            echo
            read -rp "Press Enter..."
            ;;

        3)
            repair_initramfs
            echo
            read -rp "Press Enter..."
            ;;

        4)
            repair_systemd
            echo
            read -rp "Press Enter..."
            ;;

        5)
            repair_systemd_boot
            echo
            read -rp "Press Enter..."
            ;;

        6)
            automatic_repair
            ;;

        7)
            echo
            echo "Exiting System Repair..."
            exit 0
            ;;

        *)
            echo
            echo "Invalid selection."
            sleep 1
            ;;
    esac
done

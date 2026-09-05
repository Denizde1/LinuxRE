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

# shellcheck disable=SC1091
source /opt/linuxre/lib/fsck.sh

write_repair_report() {
    local status="${1:-FAIL}"
    local timestamp
    timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    mkdir -p "$(dirname "$REPORT_FILE_PATH")" 2>/dev/null || {
        warn "Unable to create repair report directory."
        return 1
    }

    {
        echo "LinuxRE Repair Report"
        echo "Timestamp: $timestamp"
        echo "Status: $status"
        echo "Target root: ${ROOT_DEV:-unknown}"
        echo "Root UUID: ${ROOT_UUID:-unknown}"
        echo "Root filesystem: ${ROOT_FSTYPE:-unknown}"
        echo "Btrfs subvolume: ${ROOT_SUBVOL:-n/a}"
        echo "LUKS mapper: ${TARGET_LUKS_MAPPER:-n/a}"
        echo "LVM VG: ${TARGET_LVM_VG:-n/a}"
        echo "ESP: ${ESP_DEV:-unknown}"
        echo "ESP mount point: ${ESP_MOUNT:-n/a}"
        echo "Boot mode: ${TARGET_BOOT_MODE:-$(if is_uefi_system; then echo uefi; else echo non-uefi; fi)}"
        echo "Bootloader: $(detect_target_bootloader)"
        echo "Filesystem status: ${filesystem_failed:-unknown}"
        echo "Repair status: ${repair_failed:-unknown}"
        echo "Final status: ${final_failed:-unknown}"
    } > "$REPORT_FILE_PATH" || {
        warn "Unable to write repair report: $REPORT_FILE_PATH"
        return 1
    }

    chmod 600 "$REPORT_FILE_PATH" 2>/dev/null || true

    log "Repair report written to $REPORT_FILE_PATH"
}

# ==================================================
# Requirements
# ==================================================

require_root || {
    sleep 5
    exit 1
}

require_commands \
    lsblk \
    blkid \
    mount \
    umount \
    mountpoint \
    findmnt \
    awk \
    sed \
    arch-chroot \
    btrfs \
    || {
        sleep 5
        exit 1
    }

# ==================================================
# Cleanup
# ==================================================

# cleanup() is provided by common.sh.
trap 'restore_dns; cleanup_target_storage; cleanup' EXIT
# ==================================================

target_is_mounted() {
    mountpoint -q "$MNT"
}

ensure_target() {
    if target_is_mounted; then
        return 0
    fi

    log "Target is not mounted. Preparing target..."

    if ! prepare_target; then
        warn "Failed to prepare target."
        return 1
    fi

    return 0
}

unmount_target() {
    local failed=0

    # Unmount only resources mounted by LinuxRE.
    # Never recursively unmount arbitrary mounts below /mnt.

    if (( TARGET_ESP_MOUNTED )) &&
       [[ -n "$ESP_MOUNT" ]] &&
       mountpoint -q "$MNT$ESP_MOUNT"; then

        log "Unmounting target ESP..."

        if umount "$MNT$ESP_MOUNT"; then
            TARGET_ESP_MOUNTED=0
        else
            warn "Failed to unmount target ESP."
            failed=1
        fi
    fi

    if (( TARGET_ROOT_MOUNTED )) &&
       mountpoint -q "$MNT"; then

        log "Unmounting target filesystem..."

        if umount "$MNT"; then
            TARGET_ROOT_MOUNTED=0
        else
            warn "Failed to unmount target filesystem."
            failed=1
        fi
    fi

    return "$failed"
}
# ==================================================
# Header
# ==================================================

clear

echo "╔══════════════════════════════════════════╗"
echo "║          LinuxRE Automatic Repair        ║"
echo "╚══════════════════════════════════════════╝"
echo

echo "Preparing Automatic Repair..."
echo "Diagnosing your PC..."
echo

# ==================================================
# Initial target preparation
# ==================================================

if ! prepare_target; then
    die "Automatic Repair couldn't prepare a supported Linux installation."
fi

# ==================================================
# Initial filesystem diagnosis
# ==================================================

echo
echo "Checking filesystem..."
echo

filesystem_failed=0
fsck_status=0

# Filesystem checks must operate on an unmounted filesystem.
if ! unmount_target; then
    warn "Unable to unmount target before filesystem check."
    filesystem_failed=1
else
    log "Checking filesystem: $ROOT_DEV ($ROOT_FSTYPE)"

    check_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"
    fsck_status=$?

    case "$fsck_status" in
        0)
            ok "Filesystem check completed successfully."
            ;;

        1)
            warn "Filesystem errors were detected."
            filesystem_failed=1
            ;;

        *)
            warn "Filesystem check could not be completed."
            filesystem_failed=1
            ;;
    esac
fi

# Restore the target environment for the remaining diagnostics.
if ! ensure_target; then
    die "Automatic Repair couldn't restore the target after filesystem diagnosis."
fi

# ==================================================
# Initial diagnosis
# ==================================================

echo
echo "Diagnosing your PC..."
echo

failed=0

if (( filesystem_failed != 0 )); then
    failed=1
fi

verify_target || failed=1
verify_pacman || failed=1
verify_package_integrity || failed=1
verify_kernel || failed=1
verify_initramfs || failed=1
verify_systemd || failed=1
verify_systemd_boot || failed=1

echo

# ==================================================
# Nothing to repair
# ==================================================

if (( failed == 0 )); then
    echo "Automatic Repair didn't find any problems."
    sleep 5
    exit 0
fi

# ==================================================
# System update
# ==================================================

echo "Updating the target system..."
echo

if ensure_target; then
    if linuxre_chroot "$MNT" pacman -Syu --noconfirm; then
        ok "System update completed successfully."
    else
        warn "System update failed. Continuing with repair..."
    fi
else
    warn "Target could not be prepared for system update."
fi

# ==================================================
# Automatic repair
# ==================================================

clear

echo
echo "Attempting repairs..."
echo

repair_failed=0

# ==================================================
# Filesystem repair
# ==================================================

if (( filesystem_failed != 0 )); then
    log "Preparing filesystem repair..."

    # Filesystem repair must operate on an unmounted filesystem.
    if ! unmount_target; then
        warn "Failed to unmount target filesystem."
        repair_failed=1
    fi

    if (( repair_failed == 0 )); then
        if repair_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"; then
            ok "Filesystem repair completed."
        else
            warn "Filesystem repair failed or is not supported."
            repair_failed=1
        fi
    fi

    # Restore the complete target state before continuing.
    if ! ensure_target; then
        warn "Failed to restore target after filesystem repair."
        repair_failed=1
    fi
fi

# ==================================================
# Package integrity repair
# ==================================================

if ! ensure_target; then
    warn "Target is unavailable. Skipping remaining repairs."
    repair_failed=1
else
    if ! verify_package_integrity >/dev/null 2>&1; then
        log "Repairing package integrity..."

        if ! repair_package_integrity; then
            repair_failed=1
        fi
    fi
fi

# ==================================================
# Kernel repair
# ==================================================

if ensure_target; then
    if ! verify_kernel >/dev/null 2>&1; then
        log "Repairing kernel..."

        if ! repair_kernel; then
            repair_failed=1
        fi
    fi
else
    warn "Target is unavailable. Skipping kernel repair."
    repair_failed=1
fi

# ==================================================
# Initramfs / UKI repair
# ==================================================

if ensure_target; then
    if ! verify_initramfs >/dev/null 2>&1; then
        log "Repairing initramfs / UKI..."

        if ! repair_initramfs; then
            repair_failed=1
        fi
    fi
else
    warn "Target is unavailable. Skipping initramfs / UKI repair."
    repair_failed=1
fi

# ==================================================
# systemd repair
# ==================================================

if ensure_target; then
    if ! verify_systemd >/dev/null 2>&1; then
        log "Repairing systemd..."

        if ! repair_systemd; then
            repair_failed=1
        fi
    fi
else
    warn "Target is unavailable. Skipping systemd repair."
    repair_failed=1
fi

# ==================================================
# systemd-boot repair
# ==================================================

if ensure_target; then
    if ! verify_systemd_boot >/dev/null 2>&1; then
        log "Repairing systemd-boot..."

        if ! repair_systemd_boot; then
            repair_failed=1
        fi
    fi
else
    warn "Target is unavailable. Skipping systemd-boot repair."
    repair_failed=1
fi

# ==================================================
# Final target preparation
# ==================================================

echo
echo "Preparing final diagnosis..."
echo

final_failed=0

if ! ensure_target; then
    warn "Unable to prepare target for final diagnosis."
    final_failed=1
fi

# ==================================================
# Final filesystem verification
# ==================================================

if (( filesystem_failed != 0 )); then

    # Filesystem verification must operate on an unmounted filesystem.
    if ! unmount_target; then
        warn "Failed to unmount target before final filesystem check."
        final_failed=1
    fi

    if (( final_failed == 0 )); then
        echo

        log "Checking filesystem: $ROOT_DEV ($ROOT_FSTYPE)"

        check_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"
        final_fsck_status=$?

        if (( final_fsck_status != 0 )); then
            warn "Filesystem verification failed."
            final_failed=1
        else
            ok "Final filesystem verification completed successfully."
        fi
    fi

    # Restore target regardless of filesystem result so that
    # the remaining verification functions have a consistent
    # environment.
    if ! ensure_target; then
        warn "Failed to restore target after final filesystem check."
        final_failed=1
    fi
fi

# ==================================================
# Final verification
# ==================================================

echo
echo "Diagnosing your PC..."
echo

if ! ensure_target; then
    final_failed=1
else
    verify_target || final_failed=1
    verify_pacman || final_failed=1
    verify_package_integrity || final_failed=1
    verify_kernel || final_failed=1
    verify_initramfs || final_failed=1
    verify_systemd || final_failed=1
    verify_systemd_boot || final_failed=1
fi

echo

# ==================================================
# Result
# ==================================================

TARGET_BOOT_MODE="$(if is_uefi_system; then echo uefi; else echo non-uefi; fi)"

if (( repair_failed == 0 && final_failed == 0 )); then
    echo "Automatic Repair successfully repaired your PC."
    write_repair_report "PASS"
    sleep 5
    exit 0
fi

echo "Automatic Repair couldn't repair your PC."
write_repair_report "FAIL"
sleep 5
exit 1

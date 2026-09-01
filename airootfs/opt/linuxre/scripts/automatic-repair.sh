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

trap cleanup_automatic_repair EXIT

# ==================================================
# Target setup
# ==================================================

clear

echo "╔══════════════════════════════════════════╗"
echo "║          LinuxRE Automatic Repair        ║"
echo "╚══════════════════════════════════════════╝"
echo

echo "Preparing Automatic Repair..."
echo "Diagnosing your PC..."
echo

# prepare_target() owns the complete target lifecycle:
#
#   - LUKS detection/unlock
#   - LVM activation
#   - root filesystem detection/selection
#   - Btrfs subvolume detection
#   - root filesystem mounting
#   - Linux installation verification
#   - ESP detection
#   - ESP mounting
#
if ! prepare_target; then
    die "Automatic Repair couldn't prepare a supported Linux installation."
    sleep 5
    exit 1
fi

# ==================================================
# Filesystem diagnosis
# ==================================================

echo
echo "Checking filesystem..."
echo

filesystem_failed=0

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

# ==================================================
# Diagnosis
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

if linuxre_chroot "$MNT" pacman -Syu --noconfirm; then
    ok "System update completed successfully."
else
    warn "System update failed. Continuing with repair..."
fi

# ==================================================
# Automatic repair
# ==================================================

clear

echo
echo "Attempting repairs..."
echo

repair_failed=0

# --------------------------------------------------
# Filesystem repair
# --------------------------------------------------

if (( filesystem_failed != 0 )); then
    log "Preparing filesystem repair..."

    # The filesystem must not be mounted while fsck-style
    # repair operations are performed.
    if mountpoint -q "$MNT"; then
        log "Unmounting target filesystem..."

        if ! umount -R "$MNT"; then
            warn "Failed to unmount target filesystem."
            repair_failed=1
        fi
    fi

    if (( repair_failed == 0 )); then
        if ! repair_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"; then
            repair_failed=1
        fi
    fi

    if (( repair_failed == 0 )); then
        ok "Filesystem repair completed."

        # Rebuild the complete target state after filesystem repair.
        #
        # prepare_target() handles:
        #   - Btrfs subvolume detection
        #   - root mount
        #   - Linux installation verification
        #   - ESP detection
        #   - ESP mount
        #
        if ! prepare_target; then
            warn "Failed to remount repaired target."
            repair_failed=1
        fi
    fi
fi

# --------------------------------------------------
# Package integrity
# --------------------------------------------------

if ! verify_package_integrity >/dev/null 2>&1; then
    log "Repairing package integrity..."

    if ! repair_package_integrity; then
        repair_failed=1
    fi
fi

# --------------------------------------------------
# Kernel
# --------------------------------------------------

if ! verify_kernel >/dev/null 2>&1; then
    log "Repairing kernel..."

    if ! repair_kernel; then
        repair_failed=1
    fi
fi

# --------------------------------------------------
# Initramfs / UKI
# --------------------------------------------------

if ! verify_initramfs >/dev/null 2>&1; then
    log "Repairing initramfs / UKI..."

    if ! repair_initramfs; then
        repair_failed=1
    fi
fi

# --------------------------------------------------
# systemd
# --------------------------------------------------

if ! verify_systemd >/dev/null 2>&1; then
    log "Repairing systemd..."

    if ! repair_systemd; then
        repair_failed=1
    fi
fi

# --------------------------------------------------
# systemd-boot
# --------------------------------------------------

if ! verify_systemd_boot >/dev/null 2>&1; then
    log "Repairing systemd-boot..."

    if ! repair_systemd_boot; then
        repair_failed=1
    fi
fi

# ==================================================
# Final diagnosis
# ==================================================

echo
echo "Diagnosing your PC..."
echo

final_failed=0

# Filesystem repair was performed while the target was
# unmounted. Verify the filesystem again before the final
# target preparation.
if (( filesystem_failed != 0 )); then
    if mountpoint -q "$MNT"; then
        if ! umount -R "$MNT"; then
            warn "Failed to unmount target before final filesystem check."
            final_failed=1
        fi
    fi

    if (( final_failed == 0 )); then
        check_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"
        final_fsck_status=$?

        if (( final_fsck_status != 0 )); then
            final_failed=1
        fi
    fi

    # Rebuild the target state from scratch after the final
    # filesystem check.
    if (( final_failed == 0 )); then
        if ! prepare_target; then
            final_failed=1
        fi
    fi
fi

# ==================================================
# Final verification
# ==================================================

if ! verify_target; then
    final_failed=1
fi

if ! verify_pacman; then
    final_failed=1
fi

if ! verify_package_integrity; then
    final_failed=1
fi

if ! verify_kernel; then
    final_failed=1
fi

if ! verify_initramfs; then
    final_failed=1
fi

if ! verify_systemd; then
    final_failed=1
fi

if ! verify_systemd_boot; then
    final_failed=1
fi

echo

# ==================================================
# Result
# ==================================================

if (( repair_failed == 0 && final_failed == 0 )); then
    echo "Automatic Repair successfully repaired your PC."
    sleep 5
    exit 0
fi

echo "Automatic Repair couldn't repair your PC."
sleep 5
exit 1


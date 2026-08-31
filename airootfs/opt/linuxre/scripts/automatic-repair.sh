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

require_root || { sleep 5; exit 1; }
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
    || { sleep 5; exit 1; }
trap cleanup EXIT

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

if ! detect_root_filesystems; then
    die "Automatic Repair couldn't find a supported Linux installation."
    sleep 5
    exit 1
fi

for i in "${!ROOTS[@]}"; do
    dev="${ROOTS[$i]}"

    echo "[$((i + 1))] $dev"

    lsblk -no \
        SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS \
        "$dev" |
        sed 's/^/    /'

    echo
done

while true; do
    read -rp \
        "Select the Arch Linux installation to repair [1-${#ROOTS[@]}]: " \
        choice


    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
        break
    fi

    echo "Invalid selection."
done

ROOT_DEV="${ROOTS[$((choice - 1))]}"

set_root "$ROOT_DEV" || { sleep 5; exit 1; }
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

if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    detect_btrfs_subvolume || { sleep 5; exit 1; }
fi

prepare_target || { sleep 5; exit 1; }
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

# --------------------------------------------------
# System update
# --------------------------------------------------

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

        if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
            detect_btrfs_subvolume || repair_failed=1
        fi

        prepare_target || repair_failed=1
    fi
fi

# --------------------------------------------------
# Package integrity
# --------------------------------------------------

if ! verify_package_integrity >/dev/null 2>&1; then
    log "Repairing package integrity..."
    repair_package_integrity || repair_failed=1
fi

# --------------------------------------------------
# Kernel
# --------------------------------------------------

if ! verify_kernel >/dev/null 2>&1; then
    log "Repairing kernel..."
    repair_kernel || repair_failed=1
fi

# --------------------------------------------------
# Initramfs / UKI
# --------------------------------------------------

if ! verify_initramfs >/dev/null 2>&1; then
    log "Repairing initramfs / UKI..."
    repair_initramfs || repair_failed=1
fi

# --------------------------------------------------
# systemd
# --------------------------------------------------

if ! verify_systemd >/dev/null 2>&1; then
    log "Repairing systemd..."
    repair_systemd || repair_failed=1
fi

# --------------------------------------------------
# systemd-boot
# --------------------------------------------------

if ! verify_systemd_boot >/dev/null 2>&1; then
    log "Repairing systemd-boot..."
    repair_systemd_boot || repair_failed=1
fi

# ==================================================
# Final diagnosis
# ==================================================

echo
echo "Diagnosing your PC..."
echo

final_failed=0

# Filesystem was repaired before the target was
# mounted again, so verify it once more after
# unmounting the target.
if (( filesystem_failed != 0 )); then
    if mountpoint -q "$MNT"; then
        umount -R "$MNT" 2>/dev/null || true
    fi

    check_filesystem "$ROOT_DEV" "$ROOT_FSTYPE"
    final_fsck_status=$?

    if (( final_fsck_status != 0 )); then
        final_failed=1
    fi

    if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
        detect_btrfs_subvolume || final_failed=1
    fi

    prepare_target || final_failed=1
fi

verify_target || final_failed=1
verify_pacman || final_failed=1
verify_package_integrity || final_failed=1
verify_kernel || final_failed=1
verify_initramfs || final_failed=1
verify_systemd || final_failed=1
verify_systemd_boot || final_failed=1

echo

if (( repair_failed == 0 && final_failed == 0 )); then
    echo "Automatic Repair successfully repaired your PC."
    sleep 5
    exit 0
fi

echo "Automatic Repair couldn't repair your PC."
sleep 5
exit 1

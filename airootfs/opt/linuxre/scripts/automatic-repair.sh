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

set_root "$ROOT_DEV" || exit 1

if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    detect_btrfs_subvolume || exit 1
fi

prepare_target || exit 1

# ==================================================
# Diagnosis
# ==================================================

clear

echo
echo "Diagnosing your PC..."
echo

failed=0

verify_target || failed=1
verify_pacman || failed=1
verify_kernel || failed=1
verify_initramfs || failed=1
verify_systemd || failed=1
verify_systemd_boot || failed=1

echo

if (( failed == 0 )); then
    echo "Automatic Repair didn't find any problems."
    exit 0
fi

# ==================================================
# Automatic repair
# ==================================================

clear

echo
echo "Attempting repairs..."
echo

repair_failed=0

if ! verify_kernel >/dev/null 2>&1; then
    log "Repairing kernel..."
    repair_kernel || repair_failed=1
fi

if ! verify_initramfs >/dev/null 2>&1; then
    log "Repairing initramfs / UKI..."
    repair_initramfs || repair_failed=1
fi

if ! verify_systemd >/dev/null 2>&1; then
    log "Repairing systemd..."
    repair_systemd || repair_failed=1
fi

if ! verify_systemd_boot >/dev/null 2>&1; then
    log "Repairing systemd-boot..."
    repair_systemd_boot || repair_failed=1
fi

# ==================================================
# Final diagnosis
# ==================================================

clear

echo
echo "Diagnosing your PC..."
echo

final_failed=0

verify_target || final_failed=1
verify_pacman || final_failed=1
verify_kernel || final_failed=1
verify_initramfs || final_failed=1
verify_systemd || final_failed=1
verify_systemd_boot || final_failed=1

echo

if (( repair_failed == 0 && final_failed == 0 )); then
    echo "Automatic Repair successfully repaired your PC."
    exit 0
fi

echo "Automatic Repair couldn't repair your PC."
exit 1

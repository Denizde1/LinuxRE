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
    findmnt \
    awk \
    sed \
    arch-chroot \
    grub-install \
    grub-mkconfig \
    || exit 1

trap 'restore_dns; cleanup_target_storage; cleanup' EXIT

clear

echo "╔══════════════════════════════════════════╗"
echo "║          GRUB Repair (UEFI)            ║"
echo "╚══════════════════════════════════════════╝"
echo

log "Scanning for Arch Linux installations..."

if ! detect_root_filesystems; then
    die "No supported Linux root filesystems were found."
    exit 1
fi

for i in "${!ROOTS[@]}"; do
    dev="${ROOTS[$i]}"
    echo "[$((i + 1))] $dev"
    lsblk -no SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS "$dev" | sed 's/^/    /'
    echo

done

while true; do
    read -rp "Select Arch Linux root filesystem [1-${#ROOTS[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
        break
    fi
    echo "Invalid selection."
done

if ! set_root "${ROOTS[$((choice - 1))]}"; then
    die "Unable to select the target root filesystem."
    exit 1
fi

if ! prepare_target; then
    die "Failed to prepare the target system."
    exit 1
fi

if ! is_uefi_system; then
    die "GRUB UEFI repair requires a UEFI boot environment."
    exit 1
fi

if [[ -z "$ESP_DEV" ]] || [[ -z "$ESP_MOUNT" ]]; then
    detect_esp || {
        die "Unable to find the target EFI System Partition."
        exit 1
    }
    detect_esp_mount
    mount_esp || {
        die "Failed to mount the target EFI System Partition."
        exit 1
    }
fi

if ! linuxre_chroot "$MNT" pacman -Q grub >/dev/null 2>&1; then
    warn "The GRUB package is not installed in the target system."
    exit 1
fi

log "Repairing GRUB UEFI installation..."

if ! linuxre_chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux --recheck; then
    warn "GRUB UEFI installation failed."
    exit 1
fi

if ! linuxre_chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg; then
    warn "GRUB menu generation failed."
    exit 1
fi

if [[ -f "$MNT$ESP_MOUNT/EFI/ArchLinux/grubx64.efi" ]] || [[ -f "$MNT$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" ]]; then
    ok "GRUB UEFI files were created successfully."
else
    warn "GRUB installation completed but the expected EFI files were not found."
    exit 1
fi

ok "GRUB repair completed successfully."
exit 0

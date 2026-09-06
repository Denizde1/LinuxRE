#!/usr/bin/env bash

set -uo pipefail

section() {
    echo
    echo "=== $1 ==="
}

show_command() {
    local label="$1"
    shift

    printf '%s: ' "$label"
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "unavailable ($1)"
        return 0
    fi

    "$@" 2>/dev/null || echo "unavailable"
}

clear
echo "LinuxRE Read-Only Diagnostics"
echo "No mount, repair, unlock, activation, or write operation is performed."

section "LinuxRE"
echo "Version: ${LINUXRE_VERSION:-unknown}"
echo "Kernel:  $(uname -r 2>/dev/null || echo unknown)"
echo "Boot mode: $(if [[ -d /sys/firmware/efi ]]; then echo UEFI; else echo legacy/non-UEFI; fi)"

section "Block devices and mounts"
show_command "Devices" lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
show_command "Mounts" findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS

section "LUKS"
if command -v lsblk >/dev/null 2>&1; then
    lsblk -rpno NAME,FSTYPE,TYPE 2>/dev/null |
        awk '$2 == "crypto_LUKS" { print }' ||
        echo "No LUKS devices detected."
else
    echo "lsblk unavailable."
fi

section "LVM"
if command -v vgs >/dev/null 2>&1; then
    vgs --noheadings --options vg_name,vg_size,vg_free,vg_attr 2>/dev/null ||
        echo "LVM information unavailable."
else
    echo "vgs unavailable."
fi

if command -v lvs >/dev/null 2>&1; then
    lvs --noheadings --options lv_path,lv_size,lv_attr,vg_name 2>/dev/null ||
        echo "LV information unavailable."
else
    echo "lvs unavailable."
fi

section "Btrfs"
if command -v btrfs >/dev/null 2>&1; then
    btrfs filesystem show 2>/dev/null || echo "No accessible Btrfs filesystem."
    while read -r mountpoint_path fstype; do
        [[ "$fstype" == "btrfs" ]] || continue
        echo "Subvolumes at $mountpoint_path:"
        btrfs subvolume list "$mountpoint_path" 2>/dev/null ||
            echo "  unavailable"
    done < <(findmnt -rn -o TARGET,FSTYPE 2>/dev/null)
else
    echo "btrfs unavailable."
fi

section "Target and boot artifacts"
for path in \
    /mnt/etc/os-release \
    /mnt/usr/lib/systemd/systemd \
    /mnt/usr/bin/bootctl \
    /mnt/boot/grub/grub.cfg \
    /mnt/boot/loader/loader.conf \
    /mnt/efi/loader/loader.conf \
    /var/log/linuxre-repair.log \
    /var/log/linuxre-repair-report.txt
do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "Present: $path"
    else
        echo "Missing: $path"
    fi
done

if [[ -r /var/log/linuxre-repair-report.txt ]]; then
    echo
    echo "Last repair report:"
    sed -n '1,80p' /var/log/linuxre-repair-report.txt
fi

echo
read -rp "Press Enter to continue..." _

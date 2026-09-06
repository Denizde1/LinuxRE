#!/usr/bin/env bash

set -uo pipefail

show_storage_information() {
    local device fstype mountpoint

    printf '%s\n' "Storage Inspector [READ ONLY]"
    printf '%s\n' "No partition, filesystem, mount, or repair operation is performed."
    printf '\n%s\n' "Devices"
    lsblk -e7 -o NAME,MODEL,SIZE,TRAN,TYPE,FSTYPE,UUID,LABEL,MOUNTPOINTS

    printf '\n%s\n' "Mounted filesystem usage"
    df -hT

    printf '\n%s\n' "Encryption and LVM"
    if command -v cryptsetup >/dev/null 2>&1; then
        cryptsetup status --all 2>/dev/null || printf '%s\n' "No active device-mapper encryption reported."
    else
        printf '%s\n' "cryptsetup is unavailable."
    fi
    if command -v pvs >/dev/null 2>&1; then
        pvs 2>/dev/null || printf '%s\n' "No LVM physical volumes reported."
        vgs 2>/dev/null || true
        lvs 2>/dev/null || true
    else
        printf '%s\n' "LVM tools are unavailable."
    fi

    printf '\n%s\n' "Mounted Btrfs filesystems"
    while IFS= read -r device; do
        [[ -n "$device" ]] || continue
        fstype="$(findmnt -rn -S "$device" -o FSTYPE 2>/dev/null | head -n1)"
        [[ "$fstype" == btrfs ]] || continue
        mountpoint="$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n1)"
        [[ -n "$mountpoint" ]] || continue
        printf '\nDevice: %s  Mount: %s\n' "$device" "$mountpoint"
        if command -v btrfs >/dev/null 2>&1; then
            btrfs filesystem usage "$mountpoint" 2>/dev/null || true
            btrfs subvolume list "$mountpoint" 2>/dev/null || true
        fi
    done < <(findmnt -rn -o SOURCE 2>/dev/null | sort -u)
}

show_storage_information
read -r -p "Press Enter to continue..." _

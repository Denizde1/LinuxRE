#!/usr/bin/env bash

set -uo pipefail

# ==================================================
# Filesystem check
# ==================================================

check_filesystem() {
    local device="${1:-}"
    local fstype="${2:-}"

    if [[ ! -b "$device" ]]; then
        warn "Invalid block device: $device"
        return 2
    fi

    if [[ -z "$fstype" ]]; then
        fstype="$(lsblk -no FSTYPE "$device")"
    fi

    if [[ -z "$fstype" ]]; then
        warn "Unable to determine filesystem type."
        return 2
    fi

    if findmnt -S "$device" >/dev/null 2>&1; then
        warn "Filesystem is currently mounted: $device"
        return 2
    fi

    log "Checking filesystem: $device ($fstype)"

    case "$fstype" in
        ext2|ext3|ext4)
            fsck -f -n "$device"
            ;;

        btrfs)
            btrfs check "$device"
            return $?
            ;;

        f2fs)
            fsck.f2fs -n "$device"
            ;;

        vfat|exfat)
            log "Filesystem check is available, but automatic repair is disabled for $fstype."
            return 0
            ;;

        xfs)
            warn "Automatic XFS repair is not supported."
            return 2
            ;;

        ntfs|ntfs3)
            warn "Automatic NTFS repair is not supported."
            return 2
            ;;

        *)
            warn "Unsupported filesystem: $fstype"
            return 2
            ;;
    esac
}

# ==================================================
# Filesystem repair
# ==================================================

repair_filesystem() {
    local device="${1:-}"
    local fstype="${2:-}"

    if [[ ! -b "$device" ]]; then
        warn "Invalid block device: $device"
        return 1
    fi

    if findmnt -S "$device" >/dev/null 2>&1; then
        warn "Filesystem is currently mounted: $device"
        return 1
    fi

    log "Repairing filesystem: $device ($fstype)"

    case "$fstype" in
        ext2|ext3|ext4)
            fsck -fy "$device"
            ;;

        f2fs)
            fsck.f2fs -a "$device"
            ;;

        vfat|exfat)
            warn "Automatic repair is disabled for $fstype."
            return 1
            ;;

        btrfs)
            warn "Automatic Btrfs repair is disabled."
            return 1
            ;;

        xfs)
            warn "Automatic XFS repair is not supported."
            return 1
            ;;

        ntfs|ntfs3)
            warn "Automatic NTFS repair is not supported."
            return 1
            ;;

        *)
            warn "Unsupported filesystem: $fstype"
            return 1
            ;;
    esac
}

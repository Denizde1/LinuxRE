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
            require_commands fsck || return 2
            fsck -f -n "$device"
            ;;

        btrfs)
            require_commands btrfs || return 2
            # btrfs check is explicitly read-only; automatic Btrfs repair
            # is intentionally unsupported by LinuxRE.
            btrfs check --readonly "$device"
            return $?
            ;;

        f2fs)
            require_commands fsck.f2fs || return 2
            fsck.f2fs -n "$device"
            ;;

        vfat)
            require_commands fsck.fat || return 2
            fsck.fat -n "$device"
            ;;

        exfat)
            require_commands fsck.exfat || return 2
            fsck.exfat -n "$device"
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
    local repair_status=0

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
            require_commands fsck || return 1
            fsck -fy "$device"
            repair_status=$?
            ;;

        f2fs)
            require_commands fsck.f2fs || return 1
            fsck.f2fs -a "$device"
            repair_status=$?
            ;;

        vfat)
            require_commands fsck.fat || return 1
            warn "Automatic repair is disabled for vfat."
            return 1
            ;;

        exfat)
            require_commands fsck.exfat || return 1
            warn "Automatic repair is disabled for exfat."
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

    if (( repair_status != 0 )); then
        warn "Filesystem repair returned status $repair_status for $device."
        return 1
    fi

    if ! check_filesystem "$device" "$fstype" >/dev/null 2>&1; then
        warn "Filesystem verification after repair failed for $device."
        return 1
    fi

    ok "Filesystem verification succeeded for $device."
    return 0
}

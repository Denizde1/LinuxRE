#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/common.sh

# shellcheck disable=SC1091
source /opt/linuxre/lib/target.sh

# ==================================================
# DNS
# ==================================================

prepare_dns() {
    local target_resolv="$MNT/etc/resolv.conf"
    local backup="$TMP/resolv.conf.backup"
    local missing="$TMP/resolv.conf.backup.missing"

    if [[ ! -d "$MNT/etc" ]]; then
        warn "Target /etc directory does not exist."
        return 1
    fi

    # TMP must not depend on the target root mount.
    # Re-create it in case it was cleaned earlier.
    if ! mkdir -p "$TMP" 2>/dev/null; then
        warn "Failed to create LinuxRE temporary directory: $TMP"
        return 1
    fi

    if [[ -e "$backup" || -L "$backup" || -e "$missing" ]]; then
        return 0
    fi

    if [[ -e "$target_resolv" || -L "$target_resolv" ]]; then
        if ! cp -a "$target_resolv" "$backup"; then
            warn "Failed to back up target resolv.conf."
            return 1
        fi
    else
        if ! : > "$missing"; then
            warn "Failed to create DNS state marker."
            return 1
        fi
    fi

    if [[ ! -e /etc/resolv.conf ]]; then
        warn "Live environment has no /etc/resolv.conf."
        return 0
    fi

    rm -f "$target_resolv"

    if ! cp -L /etc/resolv.conf "$target_resolv"; then
        warn "Failed to copy DNS configuration."

        # Restore the original configuration immediately if possible.
        if [[ -e "$backup" || -L "$backup" ]]; then
            rm -f "$target_resolv"
            mv "$backup" "$target_resolv" 2>/dev/null || true
        elif [[ -e "$missing" ]]; then
            rm -f "$target_resolv"
        fi

        return 1
    fi

    ok "DNS configuration prepared."
    return 0
}

# ==================================================
# Restore DNS
# ==================================================

restore_dns() {
    local target_resolv="$MNT/etc/resolv.conf"
    local backup="$TMP/resolv.conf.backup"
    local missing="$TMP/resolv.conf.backup.missing"

    # If the target filesystem is no longer mounted, there is
    # nothing safe to restore here.
    if [[ ! -d "$MNT/etc" ]]; then
        return 0
    fi

    if [[ -e "$backup" || -L "$backup" ]]; then
        rm -f "$target_resolv"

        if ! mv "$backup" "$target_resolv"; then
            warn "Failed to restore target resolv.conf."
            return 1
        fi

        rm -f "$missing"
        ok "Original DNS configuration restored."
        return 0
    fi

    if [[ -e "$missing" ]]; then
        if rm -f "$target_resolv" "$missing"; then
            return 0
        fi

        warn "Failed to remove temporary DNS state."
        return 1
    fi

    return 0
}

# ==================================================
# Chroot runtime mounts
# ==================================================

CHROOT_RUNTIME_MOUNTS=()

cleanup_chroot_mounts() {
    local failed=0
    local mountpoint_path
    local remaining=()

    if ((${#CHROOT_RUNTIME_MOUNTS[@]} == 0)); then
        return 0
    fi

    for mountpoint_path in "${CHROOT_RUNTIME_MOUNTS[@]}"; do
        [[ -n "$mountpoint_path" ]] || continue

        if mountpoint -q "$mountpoint_path"; then
            log "Unmounting chroot runtime mount: $mountpoint_path"

            if ! umount --recursive "$mountpoint_path" 2>/dev/null; then
                warn "Failed to unmount chroot runtime mount: $mountpoint_path"
                remaining+=("$mountpoint_path")
                failed=1
            fi
        fi
    done

    CHROOT_RUNTIME_MOUNTS=("${remaining[@]}")

    return "$failed"
}

bind_chroot_runtime_mount() {
    local source="$1"
    local target="$2"

    [[ -n "$source" ]] || return 1

    if ! mkdir -p "$target" 2>/dev/null; then
        warn "Failed to create chroot mount point: $target"
        return 1
    fi

    if mountpoint -q "$target"; then
        return 0
    fi

    if ! mount --rbind "$source" "$target" 2>/dev/null; then
        warn "Failed to bind mount $source -> $target"
        return 1
    fi

    if ! mount --make-rslave "$target" 2>/dev/null; then
        warn "Failed to make chroot mount private: $target"
        umount --recursive "$target" 2>/dev/null || true
        return 1
    fi

    CHROOT_RUNTIME_MOUNTS+=("$target")

    return 0
}

# ==================================================
# Chroot environment
# ==================================================

prepare_chroot() {
    local esp_mounted_here=0

    if [[ ! -d "$MNT/etc" ]]; then
        warn "Target filesystem is not mounted."
        return 1
    fi

    if ! mountpoint -q "$MNT"; then
        warn "Target root is not mounted."
        return 1
    fi

    # Ensure the temporary directory exists before touching
    # anything inside the target root.
    if ! mkdir -p "$TMP" 2>/dev/null; then
        warn "Failed to create LinuxRE temporary directory: $TMP"
        return 1
    fi

    # Make sure ESP information exists.
    if [[ -z "$ESP_DEV" ]]; then
        detect_esp || return 1
    fi

    if [[ -z "$ESP_MOUNT" ]]; then
        detect_esp_mount
    fi

    if [[ -n "$ESP_DEV" ]] && [[ -n "$ESP_MOUNT" ]]; then
        if (( ! TARGET_ESP_MOUNTED )); then
            mount_esp || return 1
            esp_mounted_here=1
        fi
    fi

    # Prepare DNS first so that the original resolv.conf is backed up
    # before entering the chroot.
    if ! prepare_dns; then
        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null || true
            TARGET_ESP_MOUNTED=0
        fi

        return 1
    fi

    if ! bind_chroot_runtime_mount /dev "$MNT/dev"; then
        restore_dns || true
        cleanup_chroot_mounts

        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null || true
            TARGET_ESP_MOUNTED=0
        fi

        return 1
    fi

    if ! bind_chroot_runtime_mount /proc "$MNT/proc"; then
        restore_dns || true
        cleanup_chroot_mounts

        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null || true
            TARGET_ESP_MOUNTED=0
        fi

        return 1
    fi

    if ! bind_chroot_runtime_mount /sys "$MNT/sys"; then
        restore_dns || true
        cleanup_chroot_mounts

        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null || true
            TARGET_ESP_MOUNTED=0
        fi

        return 1
    fi

    if ! bind_chroot_runtime_mount /run "$MNT/run"; then
        restore_dns || true
        cleanup_chroot_mounts

        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null || true
            TARGET_ESP_MOUNTED=0
        fi

        return 1
    fi

    ok "Chroot environment prepared."

    return 0
}

# ==================================================
# Run command inside target chroot
# ==================================================

linuxre_chroot() {
    local target="$1"

    shift

    if [[ ! -d "$target" ]]; then
        warn "Chroot target does not exist: $target"
        return 1
    fi

    if ! mountpoint -q "$target"; then
        warn "Chroot target is not mounted: $target"
        return 1
    fi

    arch-chroot "$target" "$@"
}

# ==================================================
# Enter chroot
# ==================================================

enter_chroot() {
    local status
    local cleanup_status=0

    if ! prepare_chroot; then
        return 1
    fi

    echo
    echo "========================================"
    echo "          Entering Arch Linux"
    echo "========================================"
    echo

    arch-chroot "$MNT"
    status=$?

    if ! restore_dns; then
        cleanup_status=1
    fi

    if ! cleanup_chroot_mounts; then
        cleanup_status=1
    fi

    echo

    if (( status == 0 )); then
        ok "Exited chroot successfully."
    else
        warn "arch-chroot exited with status $status."
    fi

    if (( status != 0 )); then
        return "$status"
    fi

    return "$cleanup_status"
}

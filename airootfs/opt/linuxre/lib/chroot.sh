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

    if [[ -e "$backup" || -L "$backup" || -e "$missing" ]]; then
        return 0
    fi

    if [[ -e "$target_resolv" || -L "$target_resolv" ]]; then
        if ! cp -a "$target_resolv" "$backup"; then
            warn "Failed to back up target resolv.conf."
            return 1
        fi
    else
        : > "$missing"
    fi

    if [[ ! -e /etc/resolv.conf ]]; then
        warn "Live environment has no /etc/resolv.conf."
        return 0
    fi

    rm -f "$target_resolv"

    if ! cp -L /etc/resolv.conf "$target_resolv"; then
        warn "Failed to copy DNS configuration."
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
        rm -f "$target_resolv" "$missing"
        return 0
    fi

    return 0
}

CHROOT_RUNTIME_MOUNTS=()

cleanup_chroot_mounts() {
    local mountpoint_path

    if ((${#CHROOT_RUNTIME_MOUNTS[@]} == 0)); then
        return 0
    fi

    for mountpoint_path in "${CHROOT_RUNTIME_MOUNTS[@]}"; do
        [[ -n "$mountpoint_path" ]] || continue
        if mountpoint -q "$mountpoint_path"; then
            log "Unmounting chroot runtime mount: $mountpoint_path"
            umount --recursive "$mountpoint_path" 2>/dev/null || true
        fi
    done

    CHROOT_RUNTIME_MOUNTS=()
    return 0
}

bind_chroot_runtime_mount() {
    local source="$1"
    local target="$2"

    [[ -n "$source" ]] || return 1
    mkdir -p "$target" 2>/dev/null || return 1

    if mountpoint -q "$target"; then
        return 0
    fi

    if ! mount --rbind "$source" "$target" 2>/dev/null; then
        warn "Failed to bind mount $source -> $target"
        return 1
    fi

    mount --make-rslave "$target" 2>/dev/null || {
        warn "Failed to make chroot mount private: $target"
        umount --recursive "$target" 2>/dev/null || true
        return 1
    }

    CHROOT_RUNTIME_MOUNTS+=("$target")
    return 0
}

# ==================================================
# Chroot environment
# ==================================================

prepare_chroot() {
    if [[ ! -d "$MNT/etc" ]]; then
        warn "Target filesystem is not mounted."
        return 1
    fi

    if ! mountpoint -q "$MNT"; then
        warn "Target root is not mounted."
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
        mount_esp || return 1
    fi

    if ! prepare_dns ||
       ! bind_chroot_runtime_mount /dev "$MNT/dev" ||
       ! bind_chroot_runtime_mount /proc "$MNT/proc" ||
       ! bind_chroot_runtime_mount /sys "$MNT/sys" ||
       ! bind_chroot_runtime_mount /run "$MNT/run"; then
        restore_dns || true
        cleanup_chroot_mounts
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

    prepare_chroot || return 1

    echo
    echo "========================================"
    echo "          Entering Arch Linux"
    echo "========================================"
    echo

    arch-chroot "$MNT"

    status=$?

    restore_dns || true
    cleanup_chroot_mounts || true

    echo

    if (( status == 0 )); then
        ok "Exited chroot successfully."
    else
        warn "arch-chroot exited with status $status."
    fi

    return "$status"
}

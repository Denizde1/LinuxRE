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
    local failed=0

    if [[ -e "$backup" || -L "$backup" ]]; then
        if ! rm -f "$target_resolv"; then
            warn "Failed to remove temporary target resolv.conf."
            failed=1
        fi

        if ((failed == 0)) && ! mv "$backup" "$target_resolv"; then
            warn "Failed to restore target resolv.conf."
            failed=1
        fi

        if [[ -e "$missing" || -L "$missing" ]] &&
           ! rm -f "$missing"; then
            warn "Failed to remove DNS backup marker."
            failed=1
        fi

        if ((failed == 0)); then
            ok "Original DNS configuration restored."
        fi

        return "$failed"
    fi

    if [[ -e "$missing" || -L "$missing" ]]; then
        if ! rm -f "$target_resolv" "$missing"; then
            warn "Failed to remove temporary DNS configuration."
            return 1
        fi

        return 0
    fi

    return 0
}

CHROOT_RUNTIME_MOUNTS=()

cleanup_chroot_mounts() {
    local failed=0
    local mountpoint_path

    if ((${#CHROOT_RUNTIME_MOUNTS[@]} == 0)); then
        return 0
    fi

    if ! command -v mountpoint >/dev/null 2>&1 ||
       ! command -v umount >/dev/null 2>&1; then
        warn "Required chroot cleanup commands are unavailable."
        return 1
    fi

    for mountpoint_path in "${CHROOT_RUNTIME_MOUNTS[@]}"; do
        [[ -n "$mountpoint_path" ]] || continue

        if ! mountpoint -q "$mountpoint_path"; then
            CHROOT_RUNTIME_MOUNTS=("${CHROOT_RUNTIME_MOUNTS[@]/$mountpoint_path}")
            continue
        fi

        log "Unmounting chroot runtime mount: $mountpoint_path"

        if umount --recursive "$mountpoint_path" 2>/dev/null &&
           ! mountpoint -q "$mountpoint_path"; then
            CHROOT_RUNTIME_MOUNTS=("${CHROOT_RUNTIME_MOUNTS[@]/$mountpoint_path}")
        else
            warn "Failed to unmount chroot runtime mount: $mountpoint_path"
            failed=1
        fi
    done

    return "$failed"
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

    if ! mount --make-rslave "$target" 2>/dev/null; then
        warn "Failed to make chroot mount private: $target"
        if ! umount --recursive "$target" 2>/dev/null ||
           mountpoint -q "$target"; then
            warn "Failed to clean up chroot runtime mount: $target"
        fi
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
    local cleanup_failed=0

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
        if (( ! TARGET_ESP_MOUNTED )); then
            mount_esp || return 1
            esp_mounted_here=1
        fi
    fi

    if ! prepare_dns ||
       ! bind_chroot_runtime_mount /dev "$MNT/dev" ||
       ! bind_chroot_runtime_mount /proc "$MNT/proc" ||
       ! bind_chroot_runtime_mount /sys "$MNT/sys" ||
       ! bind_chroot_runtime_mount /run "$MNT/run"; then
        restore_dns || cleanup_failed=1
        cleanup_chroot_mounts || cleanup_failed=1
        if (( esp_mounted_here )) &&
           [[ -n "$ESP_MOUNT" ]] &&
           mountpoint -q "$MNT$ESP_MOUNT"; then
            if ! umount --recursive "$MNT$ESP_MOUNT" 2>/dev/null ||
               mountpoint -q "$MNT$ESP_MOUNT"; then
                warn "Failed to clean up target ESP mount."
                cleanup_failed=1
            else
                TARGET_ESP_MOUNTED=0
            fi
        fi

        ((cleanup_failed == 0)) ||
            warn "Chroot preparation cleanup failed."
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
    local cleanup_failed=0

    prepare_chroot || return 1

    echo
    echo "========================================"
    echo "          Entering Arch Linux"
    echo "========================================"
    echo

    arch-chroot "$MNT"

    status=$?

    restore_dns || cleanup_failed=1
    cleanup_chroot_mounts || cleanup_failed=1

    echo

    if (( status == 0 )); then
        ok "Exited chroot successfully."
    else
        warn "arch-chroot exited with status $status."
    fi

    if ((cleanup_failed != 0)); then
        warn "Chroot cleanup failed."
        if ((status == 0)); then
            status=1
        fi
    fi

    return "$status"
}

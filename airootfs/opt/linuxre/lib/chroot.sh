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

    mount_esp || return 1

    prepare_dns || return 1

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

    echo

    if (( status == 0 )); then
        ok "Exited chroot successfully."
    else
        warn "arch-chroot exited with status $status."
    fi

    return "$status"
}

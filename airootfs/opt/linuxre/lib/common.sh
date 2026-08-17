#!/usr/bin/env bash

set -uo pipefail

MNT="${MNT:-/mnt}"
TMP="${TMP:-$MNT/.linuxre}"

# ==================================================
# Logging
# ==================================================

log() {
    printf '[*] %s\n' "$*"
}

ok() {
    printf '[OK] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    return 1
}

# ==================================================
# Requirements
# ==================================================

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "This tool must be run as root."
        return 1
    fi

    return 0
}

require_commands() {
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            die "Required command not found: $cmd"
            return 1
        fi
    done

    return 0
}

# ==================================================
# Cleanup
# ==================================================

cleanup() {
    if [[ -d "$MNT" ]]; then
        umount -R "$MNT" 2>/dev/null || true
    fi

    if [[ -d "$TMP" ]]; then
        rm -rf "$TMP" 2>/dev/null || true
    fi
}

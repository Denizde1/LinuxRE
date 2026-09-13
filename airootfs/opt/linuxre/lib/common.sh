#!/usr/bin/env bash

set -uo pipefail

MNT="${MNT:-/mnt}"

# Keep LinuxRE temporary files outside the target filesystem mount.
# The target root is mounted at $MNT, so storing TMP below $MNT
# would make the temporary directory disappear behind the mount.
TMP="${TMP:-/tmp/.linuxre}"

# Ensure the temporary LinuxRE working directory exists.
mkdir -p "$TMP" 2>/dev/null || true

# ==================================================
# Logging
# ==================================================

REPORT_LOG_PATH="${REPORT_LOG_PATH:-/var/log/linuxre-repair.log}"
REPORT_FILE_PATH="${REPORT_FILE_PATH:-/var/log/linuxre-repair-report.txt}"

mkdir -p "$(dirname "$REPORT_LOG_PATH")" 2>/dev/null || true
mkdir -p "$(dirname "$REPORT_FILE_PATH")" 2>/dev/null || true

log() {
    printf '[*] %s\n' "$*"
    printf '%s\n' "$*" >> "$REPORT_LOG_PATH" 2>/dev/null || true
}

ok() {
    printf '[OK] %s\n' "$*"
    printf '%s\n' "$*" >> "$REPORT_LOG_PATH" 2>/dev/null || true
}

warn() {
    printf '[!] %s\n' "$*" >&2
    printf '%s\n' "$*" >> "$REPORT_LOG_PATH" 2>/dev/null || true
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    printf '%s\n' "$*" >> "$REPORT_LOG_PATH" 2>/dev/null || true
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
    if [[ -d "$TMP" ]]; then
        rm -rf "$TMP" 2>/dev/null || true
    fi
}

cleanup_on_exit() {
    local primary_status=$?
    local cleanup_status=0

    if declare -F restore_dns >/dev/null 2>&1 &&
       ! restore_dns; then
        cleanup_status=1
    fi

    if declare -F cleanup_chroot_mounts >/dev/null 2>&1 &&
       ! cleanup_chroot_mounts; then
        cleanup_status=1
    fi

    if declare -F cleanup_target_storage >/dev/null 2>&1 &&
       ! cleanup_target_storage; then
        cleanup_status=1
    fi

    cleanup || cleanup_status=1

    if (( primary_status != 0 )); then
        return "$primary_status"
    fi

    return "$cleanup_status"
}

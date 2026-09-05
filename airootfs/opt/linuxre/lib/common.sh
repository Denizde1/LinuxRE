#!/usr/bin/env bash

set -uo pipefail

MNT="${MNT:-/mnt}"
TMP="${TMP:-$MNT/.linuxre}"

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

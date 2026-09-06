#!/usr/bin/env bash

diagnostic_check() {
    local label="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        printf '[OK]   %s\n' "$label"
        return 0
    fi

    printf '[FAIL] %s\n' "$label"
    return 1
}

run_diagnostic_scan() {
    local issues=0

    printf '%s\n' "LinuxRE Read-only Diagnostic Scan"
    printf '%s\n\n' "No repair or disk modification is performed."

    diagnostic_check "Root filesystem is mounted" mountpoint / || issues=$((issues + 1))
    diagnostic_check "Proc filesystem is available" test -r /proc/cmdline || issues=$((issues + 1))
    diagnostic_check "Block-device inventory is available" command -v lsblk || issues=$((issues + 1))
    diagnostic_check "Network interfaces are visible" command -v ip || issues=$((issues + 1))
    diagnostic_check "UEFI or BIOS boot mode detected" bash -c \
        '[[ -d /sys/firmware/efi ]] || [[ -r /sys/firmware/efi/fw_platform_size ]] || [[ -r /proc/cmdline ]]' ||
        issues=$((issues + 1))
    diagnostic_check "Root filesystem has free space" bash -c \
        'df -P / | awk "NR == 2 && \$4 ~ /^[0-9]+$/ && \$4 > 0 { found=1 } END { exit !found }"' ||
        issues=$((issues + 1))

    printf '\nIssues detected: %d\n' "$issues"
    if ((issues == 0)); then
        printf '%s\n' "Overall: PASS"
        return 0
    fi

    printf '%s\n' "Overall: REVIEW REQUIRED"
    return 1
}

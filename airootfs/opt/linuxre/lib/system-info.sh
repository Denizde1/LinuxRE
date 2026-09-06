#!/usr/bin/env bash

system_info_value() {
    local file="$1"
    local fallback="${2:-unknown}"

    if [[ -r "$file" ]]; then
        tr '\n' ' ' < "$file" | sed 's/[[:space:]]*$//'
    else
        printf '%s\n' "$fallback"
    fi
}

show_system_information() {
    local distro kernel boot secure

    distro="$(. /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}")"
    kernel="$(uname -sr)"
    boot="BIOS/legacy"
    [[ -d /sys/firmware/efi ]] && boot="UEFI"
    secure="unknown"
    if command -v mokutil >/dev/null 2>&1 && [[ "$boot" == UEFI ]]; then
        secure="$(mokutil --sb-state 2>/dev/null | head -n1 || printf 'unavailable')"
    fi

    printf '%s\n' "System Information"
    printf '%s\n' "────────────────────────────────────────"
    printf 'Distribution : %s\n' "${distro:-unknown}"
    printf 'Architecture : %s\n' "$(uname -m)"
    printf 'Kernel       : %s\n' "$kernel"
    printf 'Boot mode    : %s\n' "$boot"
    printf 'Secure Boot  : %s\n' "$secure"
    printf 'CPU          : %s\n' "$(awk -F: '/^model name[[:space:]]*:/ {sub(/^[[:space:]]*/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || printf 'unknown')"
    printf 'CPU threads  : %s\n' "$(nproc 2>/dev/null || printf 'unknown')"
    printf 'Memory       : %s\n' "$(free -h 2>/dev/null | awk '/^Mem:/ {print $2 " total, " $3 " used, " $4 " free"}' || printf 'unknown')"
    printf 'Load         : %s\n' "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || printf 'unknown')"
    printf 'GPU          : %s\n' "$(lspci 2>/dev/null | awk -F': ' '/VGA compatible controller|3D controller|Display controller/ {print $2; found=1} END {if (!found) print "unknown"}' | paste -sd '; ' -)"
    printf '\n%s\n' "Storage"
    lsblk -e7 -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS 2>/dev/null || printf 'lsblk unavailable\n'
    printf '\n%s\n' "Network"
    ip -br addr 2>/dev/null || printf 'ip unavailable\n'
}

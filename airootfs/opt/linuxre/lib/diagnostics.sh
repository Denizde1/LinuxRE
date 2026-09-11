#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/common.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/target.sh

LINUXRE_VERSION="${LINUXRE_VERSION:-0.8}"
REPORT_MODE="${REPORT_MODE:-0}"

diagnostics_section() {
    printf '\n=== %s ===\n' "$1"
}

diagnostics_command() {
    local label="$1"
    shift
    printf '%s:\n' "$label"
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1 || printf 'unavailable (exit status %s)\n' "$?"
    else
        printf 'unavailable (%s is not installed)\n' "$1"
    fi
}

system_information() {
    diagnostics_section "System information"
    printf 'LinuxRE version: %s\n' "$LINUXRE_VERSION"
    printf 'Kernel: %s\n' "$(uname -r 2>/dev/null || printf unknown)"
    printf 'Firmware: %s\n' "$(if [[ -d /sys/firmware/efi ]]; then printf UEFI; else printf legacy/non-UEFI; fi)"
    diagnostics_command "CPU" lscpu
    diagnostics_command "Memory" free -h
    diagnostics_command "GPU" lspci -nnk -d ::0300
    diagnostics_command "PCI devices" lspci -nn
    diagnostics_command "USB devices" lsusb
    if (( REPORT_MODE )); then
        diagnostics_command "Block devices" lsblk -e7 -o NAME,PATH,MODEL,SIZE,ROTA,TRAN,TYPE,FSTYPE,LABEL,UUID,PARTTYPE,MOUNTPOINTS
    else
        diagnostics_command "Block devices" lsblk -e7 -o NAME,PATH,MODEL,SERIAL,SIZE,ROTA,TRAN,TYPE,FSTYPE,LABEL,UUID,PARTTYPE,MOUNTPOINTS
    fi
    diagnostics_command "Network interfaces" ip -br addr
    diagnostics_command "Installed live kernels" pacman -Q linux linux-lts linux-zen linux-hardened
}

storage_explorer() {
    diagnostics_section "Storage explorer"
    diagnostics_command "Devices and hierarchy" lsblk -e7 -o NAME,PATH,MODEL,SIZE,ROTA,TRAN,TYPE,FSTYPE,LABEL,UUID,PARTTYPE,MOUNTPOINTS

    if command -v lsblk >/dev/null 2>&1; then
        printf '\nEncrypted devices:\n'
        lsblk -rpno NAME,FSTYPE,TYPE,UUID 2>/dev/null |
            awk '$2 == "crypto_LUKS" { printf "  %s (LUKS UUID %s)\n", $1, $4 }'
    fi

    if command -v pvs >/dev/null 2>&1; then
        printf '\nLVM physical volumes:\n'
        pvs --noheadings --options pv_name,vg_name,pv_size,pv_free,pv_attr 2>/dev/null ||
            printf '  unavailable\n'
        printf '\nLVM volume groups:\n'
        vgs --noheadings --options vg_name,vg_size,vg_free,vg_attr,vg_active 2>/dev/null ||
            printf '  unavailable\n'
        printf '\nLVM logical volumes:\n'
        lvs --noheadings --options lv_path,vg_name,lv_size,lv_attr,lv_active 2>/dev/null ||
            printf '  unavailable\n'
    else
        printf '\nLVM tools are not installed.\n'
    fi

    if command -v findmnt >/dev/null 2>&1; then
        printf '\nMounted filesystems:\n'
        findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS
    fi
}

lvm_explorer() {
    diagnostics_section "LVM explorer"
    if ! command -v pvs >/dev/null 2>&1; then
        printf 'LVM tools are not installed.\n'
        return 0
    fi
    printf 'Physical volumes:\n'
    pvs --noheadings --options pv_name,vg_name,pv_size,pv_free,pv_attr 2>/dev/null || printf '  unavailable\n'
    printf '\nVolume groups:\n'
    vgs --noheadings --options vg_name,vg_size,vg_free,vg_attr,vg_active 2>/dev/null || printf '  unavailable\n'
    printf '\nLogical volumes:\n'
    lvs --noheadings --options lv_path,vg_name,lv_size,lv_attr,lv_active 2>/dev/null || printf '  unavailable\n'
}

luks_diagnostics() {
    diagnostics_section "LUKS diagnostics"
    if ! command -v lsblk >/dev/null 2>&1; then
        printf 'lsblk is unavailable.\n'
        return 0
    fi

    local device
    while read -r device fstype uuid; do
        [[ "$fstype" == "crypto_LUKS" ]] || continue
        printf '\n%s\n' "$device"
        printf '  UUID: %s\n' "${uuid:-unknown}"
        if command -v cryptsetup >/dev/null 2>&1; then
            cryptsetup luksDump "$device" 2>/dev/null |
                awk -F: '
                    /Version:/ || /Cipher:/ || /PBKDF:/ || /UUID:/ {
                        gsub(/^[[:space:]]+/, "", $0); print "  " $0
                    }'
        else
            printf '  cryptsetup is unavailable; metadata details skipped.\n'
        fi
    done < <(lsblk -rpno NAME,FSTYPE,UUID 2>/dev/null)

    printf '\nOpen encrypted mappings:\n'
    if command -v dmsetup >/dev/null 2>&1; then
        lsblk -rpno NAME,TYPE,FSTYPE,MOUNTPOINTS 2>/dev/null |
            awk '$2 == "crypt" || $3 == "crypto_LUKS" { print "  " $0 }'
    else
        printf '  dmsetup is unavailable.\n'
    fi
}

btrfs_snapshots() {
    diagnostics_section "Btrfs snapshots"
    if ! command -v btrfs >/dev/null 2>&1; then
        printf 'btrfs-progs is unavailable.\n'
        return 0
    fi

    local mount_path fstype
    while read -r mount_path fstype; do
        [[ "$fstype" == "btrfs" ]] || continue
        printf '\nSubvolumes at %s:\n' "$mount_path"
        btrfs subvolume list -o "$mount_path" 2>/dev/null |
            awk '
                {
                    readonly = ($0 ~ /readonly/ ? "readonly" : "writable")
                    printf "  ID %s parent %s %s path %s\n", $2, $4, readonly, substr($0, index($0, "path ") + 5)
                }' || printf '  unavailable\n'
    done < <(findmnt -rn -o TARGET,FSTYPE 2>/dev/null)
}

boot_browser() {
    diagnostics_section "Boot entries"
    local esp
    for esp in /efi /boot /boot/efi; do
        [[ -d "$esp/loader" ]] || continue
        printf 'ESP: %s\n' "$esp"
        [[ -f "$esp/loader/loader.conf" ]] && sed 's/^/  /' "$esp/loader/loader.conf"
        if [[ -d "$esp/loader/entries" ]]; then
            find "$esp/loader/entries" -maxdepth 1 -type f -name '*.conf' -print |
                sort |
                while IFS= read -r entry; do
                    printf '\n  Entry: %s\n' "${entry##*/}"
                    sed 's/^/    /' "$entry"
                done
        fi
    done
    if [[ -n "${ESP_MOUNT:-}" && -d "$MNT$ESP_MOUNT/loader" ]]; then
        printf 'Target ESP: %s\n' "$MNT$ESP_MOUNT"
        [[ -f "$MNT$ESP_MOUNT/loader/loader.conf" ]] &&
            sed 's/^/  /' "$MNT$ESP_MOUNT/loader/loader.conf"
        find "$MNT$ESP_MOUNT/loader/entries" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null |
            sort
    fi
}

fstab_diagnostics() {
    diagnostics_section "fstab diagnostics"
    local fstab="${1:-$MNT/etc/fstab}"
    [[ -r "$fstab" ]] || { printf 'fstab unavailable: %s\n' "$fstab"; return 0; }

    awk '
        /^[[:space:]]*#/ || NF == 0 { next }
        NF < 6 { print "WARNING: malformed entry at line " NR; next }
        { count[$1]++; entries[NR] = $1 }
        END {
            for (spec in count)
                if (count[spec] > 1) print "WARNING: duplicate specifier: " spec
        }' "$fstab"

    local spec path
    while read -r spec path _; do
        [[ -n "$spec" && -n "$path" ]] || continue
        if [[ "$spec" == UUID=* ]]; then
            blkid -U "${spec#UUID=}" >/dev/null 2>&1 ||
                printf 'WARNING: missing UUID for %s (%s)\n' "$path" "$spec"
        elif [[ "$spec" == /dev/* && ! -e "$spec" ]]; then
            printf 'WARNING: missing device for %s (%s)\n' "$path" "$spec"
        fi
    done < <(awk '!/^[[:space:]]*#/ && NF >= 6 { print $1, $2, $3 }' "$fstab")
}

package_diagnostics() {
    diagnostics_section "Pacman diagnostics"
    local cache="${MNT:-/mnt}/var/cache/pacman/pkg"
    if [[ -d "$cache" ]]; then
        printf 'Cached packages: %s\n' "$(find "$cache" -maxdepth 1 -type f -name '*.pkg.tar.*' | wc -l)"
        find "$cache" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '  %f\n' | sort
    else
        printf 'Package cache unavailable: %s\n' "$cache"
    fi
    if [[ -d "${MNT:-/mnt}" ]] && mountpoint -q "${MNT:-/mnt}" 2>/dev/null; then
        local output
        output="$(arch-chroot "$MNT" env LC_ALL=C pacman -Qkk 2>&1)" || {
            printf 'Package integrity check failed.\n'
            return 0
        }
        printf '%s\n' "$output" |
            awk '/missing files|altered files/ && !/0 missing files|0 altered files/ { print "  " $0 }'
    else
        printf 'Target is not mounted; package integrity check skipped.\n'
    fi
}

network_diagnostics() {
    diagnostics_section "Network diagnostics"
    local interface
    while read -r interface state address; do
        if (( REPORT_MODE )); then
            printf '[%s] %s state=%s\n' \
                "$([[ "$state" == UP ]] && printf OK || printf WARNING)" \
                "$interface" "$state"
        else
            printf '[%s] %s state=%s address=%s\n' \
                "$([[ "$state" == UP ]] && printf OK || printf WARNING)" \
                "$interface" "$state" "${address:--}"
        fi
    done < <(ip -o -br addr 2>/dev/null | awk '{ print $1, $2, $3 }')
    printf '\nDefault route:\n'
    ip route show default 2>/dev/null || printf '  missing\n'
    printf '\nDNS:\n'
    if command -v resolvectl >/dev/null 2>&1; then resolvectl status 2>/dev/null; else cat /etc/resolv.conf 2>/dev/null; fi
    if getent hosts archlinux.org >/dev/null 2>&1; then
        printf '[OK] DNS resolution\n'
    else
        printf '[WARNING] DNS resolution unavailable\n'
    fi
}

user_diagnostics() {
    diagnostics_section "Target users"
    local passwd_file="${MNT:-/mnt}/etc/passwd"
    [[ -r "$passwd_file" ]] || { printf 'Target passwd file unavailable.\n'; return 0; }
    if (( REPORT_MODE )); then
        awk -F: '$3 >= 1000 || $1 == "root" { print "  " $1 " UID=" $3 " shell=" $7 }' "$passwd_file"
    else
        awk -F: '$3 >= 1000 || $1 == "root" { print "  " $1 " UID=" $3 " home=" $6 " shell=" $7 }' "$passwd_file"
    fi
}

journal_diagnostics() {
    diagnostics_section "Journal and systemd diagnostics"
    if [[ -d "${MNT:-/mnt}/var/log/journal" ]]; then
        printf 'Target persistent journal: available\n'
        journalctl --directory="${MNT:-/mnt}/var/log/journal" -p err..alert -n 30 --no-pager 2>/dev/null ||
            printf 'Unable to read target journal.\n'
    else
        printf 'Target persistent journal: unavailable\n'
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --failed --no-pager 2>/dev/null || printf 'Live systemd failed-unit query unavailable.\n'
    fi
}

write_report() {
    local report="${1:-${REPORT_FILE_PATH:-/var/log/linuxre-report.txt}}"
    mkdir -p "$(dirname "$report")" || return 1
    REPORT_MODE=1
    {
        printf 'LinuxRE %s Recovery Report\n' "$LINUXRE_VERSION"
        printf 'Generated: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        system_information
        storage_explorer
        luks_diagnostics
        btrfs_snapshots
        boot_browser
        fstab_diagnostics
        package_diagnostics
        network_diagnostics
        user_diagnostics
        journal_diagnostics
    } > "$report"
    REPORT_MODE=0
    chmod 600 "$report"
    printf 'Recovery report written to %s\n' "$report"
}

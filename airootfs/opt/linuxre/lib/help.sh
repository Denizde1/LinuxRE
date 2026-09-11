#!/usr/bin/env bash

set -uo pipefail

LINUXRE_MORE_HELP_URL='https://youtu.be/dQw4w9WgXcQ?si=LemS76Xh1sltnE1L'
LINUXRE_MORE_HELP_PAGE='/opt/linuxre/more-help.html'

linuxre_help_print() {
    echo "LinuxRE is an Arch Linux recovery environment. It safely inspects a target system's root disk, boot setup, filesystems, and network/application state."
    echo
    echo "Integrated diagnostics: Show disk, LUKS/LVM, Btrfs, systemd-boot, pacman, network, and journal data in focused menu sections."
    echo
    echo "Automatic Repair: Checks filesystems, package integrity, kernel/initramfs, systemd, and boot configuration, then repairs supported problems when needed."
    echo
    echo "Disk / partition operations: Inspect disks and partitions and manage root/ESP selection and mounts. Destructive operations always require careful verification."
    echo
    echo "LUKS and LVM diagnostics: Show encrypted devices, mappings, VG/LV hierarchy, and activation state with a safe inspection and reporting focus."
    echo
    echo "Btrfs snapshot browser: Lists snapshots and subvolumes with read-only/writable state. It is for inspection, not restoration."
    echo
    echo "systemd-boot diagnostics: Shows loader.conf, entries, EFI paths, and default/timeout settings without destructive changes."
    echo
    echo "Pacman integrity/cache diagnostics: Identify damaged packages and missing files and assess cached packages for offline reinstalls."
    echo
    echo "Network diagnostics: Check interfaces, IP configuration, routes, DNS, and internet access for a quick view of network problems."
    echo
    echo "Recovery report: Combines LinuxRE version, storage, boot, pacman, and network results in one report without unnecessary sensitive data."
    echo
    echo "Common situations:"
    echo "- Root filesystem not found: The target disk may not be selected or mounted correctly."
    echo "- LUKS is locked: The encrypted device may need to be opened and mapped before target preparation."
    echo "- No Btrfs snapshots: This is normal; snapshot browsing is informational only."
    echo "- Pacman integrity problems: Package files may be damaged or missing; target only required packages instead of performing a full upgrade."
    echo "- Boot problem: The ESP, loader.conf, kernel/initramfs, or systemd-boot configuration may be inconsistent."
    echo "- Network problem: Network diagnostics identifies missing DNS, routes, or gateway access."
}

linuxre_open_more_help() {
    local help_page="${LINUXRE_MORE_HELP_PAGE}"

    if command -v firefox >/dev/null 2>&1 && [[ -f "$help_page" ]]; then
        firefox --new-window "$help_page" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v xdg-open >/dev/null 2>&1 && [[ -f "$help_page" ]]; then
        xdg-open "$help_page" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v gio >/dev/null 2>&1 && [[ -f "$help_page" ]]; then
        gio open "$help_page" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v sensible-browser >/dev/null 2>&1 && [[ -f "$help_page" ]]; then
        sensible-browser "$help_page" >/dev/null 2>&1 || true
        return 0
    fi

    echo "Open this link in your browser: ${LINUXRE_MORE_HELP_URL}"
    return 0
}

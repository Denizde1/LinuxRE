#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/v08-diagnostics.sh

cleanup_recovery_center() {
    cleanup_target_storage || true
}

trap cleanup_recovery_center EXIT

pause() {
    read -r -p "Press Enter to continue..." _
}

prepare_target_for_diagnostics() {
    if mountpoint -q "$MNT"; then
        ok "Target is already mounted at $MNT."
        return 0
    fi

    detect_root_filesystems || return 1
    if ((${#ROOTS[@]} == 0)); then
        warn "No supported Arch Linux root filesystems were found."
        return 1
    fi

    local index
    echo "Detected root filesystems:"
    for index in "${!ROOTS[@]}"; do
        printf '  [%d] %s\n' "$((index + 1))" "${ROOTS[$index]}"
    done

    while true; do
        read -r -p "Select target root [1-${#ROOTS[@]}]: " index
        if [[ "$index" =~ ^[0-9]+$ ]] &&
           ((index >= 1 && index <= ${#ROOTS[@]})); then
            break
        fi
        printf 'Invalid selection.\n'
    done

    set_root "${ROOTS[$((index - 1))]}" || return 1
    prepare_target
}

while true; do
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║       LinuxRE v0.8 Recovery Center       ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) System and hardware information"
    echo "  2) Storage explorer (LUKS/LVM)"
    echo "  3) Btrfs snapshot browser"
    echo "  4) Boot entry browser"
    echo "  5) fstab diagnostics"
    echo "  6) Pacman integrity and cache diagnostics"
    echo "  7) Network diagnostics"
    echo "  8) Target users"
    echo "  9) Journal/systemd diagnostics"
    echo " 10) Prepare target for diagnostics"
    echo " 11) Write complete recovery report"
    echo " 12) Help / Yardım"
    echo
    echo "  0) Back"
    echo
    read -r -p "Select an option: " choice

    case "$choice" in
        1) clear; v08_system_information; pause ;;
        2) clear; v08_storage_explorer; v08_luks_diagnostics; pause ;;
        3) clear; v08_btrfs_snapshots; pause ;;
        4) clear; v08_boot_browser; pause ;;
        5) clear; v08_fstab_diagnostics; pause ;;
        6) clear; v08_package_diagnostics; pause ;;
        7) clear; v08_network_diagnostics; pause ;;
        8) clear; v08_user_diagnostics; pause ;;
        9) clear; v08_journal_diagnostics; pause ;;
        10) clear; prepare_target_for_diagnostics; pause ;;
        11) clear; v08_write_report; pause ;;
        12) bash /opt/linuxre/tools/help.sh ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

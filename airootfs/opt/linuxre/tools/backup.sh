#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/backup.sh

while true; do
    clear
    printf '%s\n\n' "Backup and Export"
    printf '%s\n' "  1) Back up configuration and package list [WRITES BACKUP]"
    printf '%s\n\n' "  0) Back"
    read -r -p "Select an option: " choice

    case "$choice" in
        1) clear; create_linuxre_backup; read -r -p "Press Enter to continue..." _ ;;
        0) exit 0 ;;
        *) printf '%s\n' "Invalid option."; sleep 1 ;;
    esac
done

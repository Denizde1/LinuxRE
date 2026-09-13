#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/help.sh

pause() {
    read -r -p "Press Enter to continue..." _
}

while true; do
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║              LinuxRE Help                ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    linuxre_help_print
    echo
    echo "  1) More Help"
    echo
    echo "  0) Back"
    echo
    if ! read -r -p "Select an option: " choice; then
        exit 0
    fi

    case "$choice" in
        1)
            clear
            linuxre_open_more_help
            pause
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac
done

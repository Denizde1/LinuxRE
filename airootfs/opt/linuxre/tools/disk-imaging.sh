#!/usr/bin/env bash

set -uo pipefail

while true; do
    clear

    echo "========================================"
    echo "           Disk Imaging"
    echo "========================================"
    echo
    echo "1) Create System Image"
    echo "2) Restore System Image"
    echo "3) Clone Disk"
    echo "4) Back"
    echo

    read -rp "Select an option: " choice

    case "$choice" in
        1)
            sudo bash /opt/linuxre/lib/create-system-image.sh
            read -rp "Press Enter to go back to menu..."
            ;;
        2)
            sudo bash /opt/linuxre/lib/restore-system-image.sh
            read -rp "Press Enter to go back to menu..."
            ;;
        3)  sudo bash /opt/linuxre/lib/clone-disk.sh
            read -rp "Press Enter to go back to menu..."
            ;;
        4)
            exit 0
            ;;
        *)
            echo
            echo "Invalid option."
            sleep 2
            ;;
    esac
done

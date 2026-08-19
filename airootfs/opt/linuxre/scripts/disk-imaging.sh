#!/usr/bin/env bash

set -uo pipefail

LIB_DIR="/opt/linuxre/lib"

while true; do
    clear

    echo "========================================"
    echo "           Disk Imaging"
    echo "========================================"
    echo
    echo "1) Create System Image"
    echo "2) Restore System Image"
    echo "3) Back"
    echo

    read -rp "Select an option: " choice

    case "$choice" in
        1)
            "$LIB_DIR/create-system-image.sh"
            read -rp "Press Enter to continue..."
            ;;
        2)
            "$LIB_DIR/restore-system-image.sh"
            read -rp "Press Enter to continue..."
            ;;
        3)
            exit 0
            ;;
        *)
            echo
            echo "Invalid option."
            sleep 2
            ;;
    esac
done

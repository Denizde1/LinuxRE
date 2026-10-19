#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║             Filesystem Check             ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) Check filesystem"
    echo "  2) List filesystems"
    echo
    echo "  0) Back"
    echo

    if ! read -rp "Select an option: " c; then
        echo
        exit 0
    fi

    case "$c" in
        1)
            clear

            echo "Available filesystems:"
            echo
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
            echo

            read -rp "Device (e.g. /dev/sda2): " device

            if [[ ! -b "$device" ]]; then
                echo
                echo "Invalid block device."
                read -rp "Press Enter to continue..." _
                continue
            fi

            if findmnt -S "$device" >/dev/null 2>&1; then
                echo
                echo "ERROR: The filesystem is currently mounted."
                echo "Unmount it before running a filesystem check."
                read -rp "Press Enter to continue..." _
                continue
            fi

            fstype=$(lsblk -no FSTYPE "$device")

            echo
            echo "Device:     $device"
            echo "Filesystem: ${fstype:-Unknown}"
            echo

            read -rp "Run read-only filesystem check on this device? (y/n): " confirm

            if [[ "$confirm" != "y" ]]; then
                echo "Check cancelled."
                sleep 1
                continue
            fi

            sudo bash -c '
                set -uo pipefail
                source /opt/linuxre/lib/common.sh
                source /opt/linuxre/lib/fsck.sh
                trap cleanup_on_exit EXIT
                check_filesystem "$1" "$2"
            ' bash "$device" "$fstype"

            echo
            read -rp "Press Enter to continue..." _
            ;;

        2)
            clear
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
            echo
            read -rp "Press Enter to continue..." _
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

#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║                Disk Tools                ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) KDE Partition Manager"
    echo "  2) GParted"
    echo "  3) List Block Devices"
    echo "  4) Filesystem Information"
    echo "  5) cfdisk"
    echo "  6) parted"
    echo "  7) Disk Health (SMART)"
    echo "  8) NVMe Information"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1) sudo partitionmanager ;;
        2) sudo gparted ;;
        3)
            clear
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
            read -rp "Press Enter to continue..." _
            ;;
        4)
            clear
            blkid
            read -rp "Press Enter to continue..." _
            ;;
        5) sudo cfdisk ;;
        6) sudo parted ;;
        7) sudo gsmartcontrol ;;
        8)
            clear
            if command -v nvme >/dev/null 2>&1; then
                nvme list
            else
                echo "nvme-cli is not installed."
            fi
            read -rp "Press Enter to continue..." _
            ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

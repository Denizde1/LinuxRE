#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║              Mount Manager               ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) List partitions"
    echo "  2) Mount partition"
    echo "  3) Unmount partition"
    echo "  4) Show mounted filesystems"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1)
            clear
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
            read -rp "Press Enter to continue..." _
            ;;

        2)
            clear
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
            echo
            read -rp "Partition (e.g. /dev/sda2): " device
            read -rp "Mount point (e.g. /mnt): " mountpoint

            if [[ -b "$device" ]]; then
                sudo mkdir -p "$mountpoint"

                if sudo mount "$device" "$mountpoint"; then
                    echo
                    echo "Mounted successfully."
                else
                    echo
                    echo "Mount failed."
                fi
            else
                echo "Invalid block device."
            fi

            read -rp "Press Enter to continue..." _
            ;;

        3)
            clear
            findmnt -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL
            echo
            read -rp "Mount point to unmount: " mountpoint

            if sudo umount "$mountpoint"; then
                echo "Unmounted successfully."
            else
                echo "Unmount failed."
            fi

            read -rp "Press Enter to continue..." _
            ;;

        4)
            clear
            findmnt
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

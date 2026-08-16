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

    read -rp "Select an option: " c

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

            read -rp "Run filesystem check on this device? (y/n): " confirm

            if [[ "$confirm" != "y" ]]; then
                echo "Check cancelled."
                sleep 1
                continue
            fi

            case "$fstype" in
                ext2|ext3|ext4)
                    sudo fsck -f "$device"
                    ;;

                btrfs)
                    sudo btrfs check "$device"
                    ;;

                xfs)
                    echo "XFS filesystem detected."
                    echo "Use xfs_repair for repair operations."
                    ;;

                f2fs)
                    sudo fsck.f2fs "$device"
                    ;;

                vfat)
                    sudo fsck.fat -a "$device"
                    ;;

                exfat)
                    sudo fsck.exfat "$device"
                    ;;

                ntfs|ntfs3)
                    sudo ntfsfix "$device"
                    ;;

                *)
                    echo "Unsupported or unknown filesystem: ${fstype:-unknown}"
                    ;;
            esac

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

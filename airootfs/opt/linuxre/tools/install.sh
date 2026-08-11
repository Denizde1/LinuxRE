#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║               Installation               ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) Archinstall"
    echo "  2) Manual Installation Guide"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1) sudo archinstall ;;
        2)
            clear
            echo "Manual Arch Installation"
            echo "────────────────────────────"
            echo
            echo "Typical steps:"
            echo
            echo "  1. Partition disks"
            echo "  2. Format filesystems"
            echo "  3. Mount filesystems"
            echo "  4. pacstrap /mnt base linux linux-firmware"
            echo "  5. genfstab -U /mnt >> /mnt/etc/fstab"
            echo "  6. arch-chroot /mnt"
            echo
            read -rp "Press Enter to continue..." _
            ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

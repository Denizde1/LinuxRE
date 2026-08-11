#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║                 Recovery                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) Arch Chroot"
    echo "  2) GRUB Repair"
    echo "  3) TestDisk"
    echo "  4) PhotoRec"
    echo "  5) SMART / Disk Health"
    echo "  6) ddrescue"
    echo "  7) File System Tools"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1)
            clear
            echo "Arch Chroot"
            echo "────────────────────────────"
            echo
            echo "Mount your Linux installation first:"
            echo
            echo "  mount /dev/sdXY /mnt"
            echo "  arch-chroot /mnt"
            echo
            read -rp "Press Enter to continue..." _
            ;;
        2)
            clear
            echo "GRUB Repair"
            echo "────────────────────────────"
            echo
            echo "Typical commands:"
            echo
            echo "  grub-install ..."
            echo "  grub-mkconfig -o /boot/grub/grub.cfg"
            echo
            read -rp "Press Enter to continue..." _
            ;;
        3) testdisk ;;
        4) photorec ;;
        5) gsmartcontrol ;;
        6)
            clear
            if command -v ddrescue >/dev/null 2>&1; then
                echo "GNU ddrescue"
                echo "────────────────────────────"
                echo
                echo "Run 'ddrescue --help' for usage."
                echo
                ddrescue --help | head -30
            else
                echo "ddrescue is not installed."
            fi
            read -rp "Press Enter to continue..." _
            ;;
        7)
            clear
            echo "Available filesystem tools:"
            echo
            echo "  btrfs-progs"
            echo "  e2fsprogs"
            echo "  xfsprogs"
            echo "  f2fs-tools"
            echo "  dosfstools"
            echo "  exfatprogs"
            echo "  ntfs-3g"
            echo
            read -rp "Press Enter to continue..." _
            ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

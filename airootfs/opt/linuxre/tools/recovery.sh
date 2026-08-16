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
    echo "  8) Filesystem Check"
    echo "  9) System Repair (For systemd-boot)"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1)
            clear
            sudo bash /opt/linuxre/scripts/auto-chroot.sh
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

        8) sudo bash /opt/linuxre/tools/fsck.sh ;;
        9) sudo bash /opt/linuxre/scripts/system-repair.sh ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

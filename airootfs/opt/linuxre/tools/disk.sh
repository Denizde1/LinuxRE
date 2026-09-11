#!/bin/bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/diagnostics.sh

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
    echo "  9) Mount Manager"
    echo " 10) System Image Recovery"
    echo " 11) Storage Explorer"
    echo " 12) LUKS Diagnostics"
    echo " 13) LVM Explorer"
    echo " 14) Btrfs Snapshot Browser"
    echo " 15) fstab Diagnostics"
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

        9) bash /opt/linuxre/tools/mountmanager.sh ;;
        11) clear; storage_explorer; read -r -p "Press Enter to continue..." _ ;;
        12) clear; luks_diagnostics; read -r -p "Press Enter to continue..." _ ;;
        13) clear; lvm_explorer; read -r -p "Press Enter to continue..." _ ;;
        14) clear; btrfs_snapshots; read -r -p "Press Enter to continue..." _ ;;
        15) clear; fstab_diagnostics; read -r -p "Press Enter to continue..." _ ;;
        10) bash /opt/linuxre/tools/disk-imaging.sh ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

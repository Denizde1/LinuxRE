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
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1)
            clear

            # Arch Chroot
            # shellcheck disable=SC1091
            source /opt/linuxre/lib/common.sh
            # shellcheck disable=SC1091
            source /opt/linuxre/lib/target.sh
            # shellcheck disable=SC1091
            source /opt/linuxre/lib/chroot.sh

            if ! sudo -v; then
                read -rp "Press Enter to continue..." _
                continue
            fi

            sudo bash -c '
                source /opt/linuxre/lib/common.sh
                source /opt/linuxre/lib/target.sh
                source /opt/linuxre/lib/chroot.sh

                require_root || exit 1

                if ! detect_root_filesystems; then
                    warn "No supported Linux root filesystems were found."
                    exit 1
                fi

                echo
                echo "Detected root filesystems:"
                echo

                for i in "${!ROOTS[@]}"; do
                    dev="${ROOTS[$i]}"

                    echo "[$((i + 1))] $dev"

                    lsblk -no SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS "$dev" |
                        sed "s/^/    /"

                    echo
                done

                while true; do
                    read -rp "Select Arch Linux root filesystem [1-${#ROOTS[@]}]: " choice

                    if [[ "$choice" =~ ^[0-9]+$ ]] &&
                       (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
                        break
                    fi

                    echo "Invalid selection."
                done

                ROOT_DEV="${ROOTS[$((choice - 1))]}"

                set_root "$ROOT_DEV" || exit 1

                if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
                    detect_btrfs_subvolume || exit 1
                fi

                prepare_target || exit 1

                enter_chroot
            '

            read -rp "Press Enter to continue..."
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
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

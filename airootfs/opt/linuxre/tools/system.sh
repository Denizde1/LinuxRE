#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║            System Diagnostics            ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) btop"
    echo "  2) fastfetch"
    echo "  3) System Information"
    echo "  4) Hardware Information"
    echo "  5) Sensors / Temperatures"
    echo "  6) PCI Devices"
    echo "  7) USB Devices"
    echo "  8) Log Viewer"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1) btop ;;
        2) clear; fastfetch; read -rp "Press Enter to continue..." _ ;;
        3) clear; inxi -Fxxxz; read -rp "Press Enter to continue..." _ ;;
        4) clear; hwinfo; read -rp "Press Enter to continue..." _ ;;
        5) clear; sensors; read -rp "Press Enter to continue..." _ ;;
        6) clear; lspci; read -rp "Press Enter to continue..." _ ;;
        7) clear; lsusb; read -rp "Press Enter to continue..." _ ;;
        8) bash /opt/linuxre/tools/logs.sh ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

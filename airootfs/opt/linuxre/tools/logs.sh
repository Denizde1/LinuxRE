#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║                Log Viewer                ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) Current boot log"
    echo "  2) Kernel log"
    echo "  3) Errors and warnings"
    echo "  4) Follow live logs"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1)
            clear
            journalctl -b
            read -rp "Press Enter to continue..." _
            ;;

        2)
            clear
            journalctl -k -b
            read -rp "Press Enter to continue..." _
            ;;

        3)
            clear
            journalctl -b -p warning
            read -rp "Press Enter to continue..." _
            ;;

        4)
            clear
            echo "Following live logs..."
            echo "Press Ctrl+C to stop."
            echo
            journalctl -f
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

#!/bin/bash

while true; do
    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║                 Network                  ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    echo "  1) Firefox"
    echo "  2) NetworkManager"
    echo "  3) Ping"
    echo "  4) Network Information"
    echo "  5) Terminal"
    echo
    echo "  0) Back"
    echo

    read -rp "Select an option: " c

    case "$c" in
        1) firefox ;;
        2) sudo nmtui ;;
        3)
            read -rp "Host or IP: " h
            if [[ -n "$h" ]]; then
                ping -c 4 "$h"
            fi
            read -rp "Press Enter to continue..." _
            ;;
        4)
            clear
            echo "Network interfaces:"
            ip -br addr
            echo
            echo "Routes:"
            ip route
            echo
            echo "DNS:"
            resolvectl status 2>/dev/null || cat /etc/resolv.conf
            read -rp "Press Enter to continue..." _
            ;;
        5) clear; bash ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

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
    echo "  5) Network Diagnostics [READ ONLY]"
    echo "  6) Terminal"
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
        5)
            clear
            echo "Network Diagnostics"
            echo "────────────────────────────"
            echo
            ip -br link
            echo
            ip -br addr
            echo
            ip route
            echo
            if getent hosts archlinux.org >/dev/null 2>&1; then
                echo "DNS: working"
            else
                echo "DNS: unavailable"
            fi
            if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1; then
                echo "Internet: reachable"
            else
                echo "Internet: unreachable"
            fi
            read -rp "Press Enter to continue..." _
            ;;
        6) clear; bash ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

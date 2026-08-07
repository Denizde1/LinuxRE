#!/bin/bash
clear
echo "=== Network ==="
echo "1) Firefox"
echo "2) nmtui"
echo "3) Ping"
echo "4) Shell"
echo "0) Back"
read -rp "> " c
case "$c" in
    1) firefox ;;
    2) nmtui ;;
    3) read -rp "Host: " h; ping "$h" ;;
    4) bash ;;
esac

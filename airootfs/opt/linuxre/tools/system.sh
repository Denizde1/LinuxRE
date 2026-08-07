#!/bin/bash
clear
echo "=== System ==="
echo "1) btop"
echo "2) fastfetch"
echo "3) inxi"
echo "4) hwinfo"
echo "5) sensors"
echo "0) Back"
read -rp "> " c
case "$c" in
    1) btop ;;
    2) fastfetch ;;
    3) inxi -F ;;
    4) hwinfo ;;
    5) sensors ;;
esac

#!/bin/bash
clear
echo "=== Installation ==="
echo "1) Archinstall"
echo "2) Manual install info"
echo "0) Back"
read -rp "> " c
case "$c" in
    1) archinstall ;;
    2) echo "pacstrap -> genfstab -> arch-chroot"; read -rp "Enter..." ;;
esac

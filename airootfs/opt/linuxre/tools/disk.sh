#!/bin/bash
clear
echo "=== Disk Tools ==="
echo "1) KDE Partition Manager"
echo "2) GParted"
echo "3) lsblk"
echo "4) blkid"
echo "5) cfdisk"
echo "6) parted"
echo "0) Back"
read -rp "> " c
case "$c" in
    1) partitionmanager ;;
    2) gparted ;;
    3) lsblk; read -rp "Enter..." ;;
    4) blkid; read -rp "Enter..." ;;
    5) cfdisk ;;
    6) parted ;;
esac

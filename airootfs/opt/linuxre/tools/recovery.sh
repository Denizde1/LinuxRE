#!/bin/bash
clear
echo "=== Recovery ==="
echo "1) Chroot"
echo "2) GRUB"
echo "3) TestDisk"
echo "4) PhotoRec"
echo "5) SMART"
echo "0) Back"
read -rp "> " c
case "$c" in
    1) echo "Use: arch-chroot /mnt"; read -rp "Enter..." ;;
    2) echo "Use: grub-install && grub-mkconfig"; read -rp "Enter..." ;;
    3) testdisk ;;
    4) photorec ;;
    5) gsmartcontrol ;;
esac

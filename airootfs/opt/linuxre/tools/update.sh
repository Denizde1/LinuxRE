#!/bin/bash

clear

echo "╔══════════════════════════════════════════╗"
echo "║              System Update               ║"
echo "╚══════════════════════════════════════════╝"
echo

echo "This will update the LinuxRE environment."
echo

read -rp "Do you want to continue? (y/n): " confirm

if [[ "$confirm" != "y" ]]; then
    echo "Update cancelled."
    exit 0
fi

echo
echo "🔄 Updating package databases and packages..."
echo

if ! sudo -v; then
    echo "❌ Sudo authentication failed."
    read -rp "Press Enter to continue..." _
    exit 1
fi

if sudo pacman -Syu --noconfirm; then
    echo
    echo "✅ Update completed successfully."
else
    echo
    echo "❌ Update failed."
    read -rp "Press Enter to continue..." _
    exit 1
fi

echo
read -rp "Press Enter to continue..." _
exit 0

#!/usr/bin/env bash

set -uo pipefail

echo "========================================"
echo "            Clone Disk"
echo "========================================"
echo

if ! command -v ddrescue >/dev/null 2>&1; then
    echo "Error: ddrescue is not installed."
    exit 1
fi

echo "Available disks:"
echo

lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS

echo
read -rp "Source disk (example: /dev/nvme0n1): " source
read -rp "Target disk (example: /dev/sda): " target

if [[ ! -b "$source" ]]; then
    echo
    echo "Error: Source device does not exist."
    exit 1
fi

if [[ ! -b "$target" ]]; then
    echo
    echo "Error: Target device does not exist."
    exit 1
fi

if [[ "$source" == "$target" ]]; then
    echo
    echo "Error: Source and target cannot be the same device."
    exit 1
fi

echo
echo "Source: $source"
echo "Target: $target"
echo

echo "========================================"
echo "             WARNING!"
echo "========================================"
echo
echo "All existing data on the TARGET device"
echo "will be permanently overwritten."
echo

read -rp "Type CLONE to continue: " confirm

if [[ "$confirm" != "CLONE" ]]; then
    echo
    echo "Cancelled."
    exit 0
fi

map="/tmp/linuxre-${source##*/}-to-${target##*/}.map"

echo
echo "Source: $source"
echo "Target: $target"
echo "Map:    $map"
echo

echo "Cloning disk..."
echo

ddrescue --force "$source" "$target" "$map"

status=$?

echo

if [[ $status -eq 0 ]]; then
    echo "Disk cloned successfully."
else
    echo "Cloning finished with errors."
    echo "The map file was preserved:"
    echo "$map"
fi

exit "$status"

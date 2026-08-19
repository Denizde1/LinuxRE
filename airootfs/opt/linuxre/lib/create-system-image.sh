#!/usr/bin/env bash

set -uo pipefail

echo "========================================"
echo "       Create System Image"
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
read -rp "Source disk or partition (example: /dev/nvme0n1): " source
read -rp "Destination image path (example: /mnt/backup/system.img): " image

if [[ ! -b "$source" ]]; then
    echo
    echo "Error: Source device does not exist."
    exit 1
fi

if [[ -z "$image" ]]; then
    echo
    echo "Error: Destination path cannot be empty."
    exit 1
fi

map="${image}.map"

echo
echo "Source : $source"
echo "Image  : $image"
echo "Map    : $map"
echo

read -rp "Start imaging? This may take a long time. [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

mkdir -p "$(dirname "$image")" || {
    echo "Error: Could not access destination directory."
    exit 1
}

echo
echo "Creating system image..."
echo

ddrescue --force --no-scrape "$source" "$image" "$map"

status=$?

echo

if [[ $status -eq 0 ]]; then
    echo "System image created successfully."
    echo
    echo "Image: $image"
    echo "Map:   $map"
else
    echo "Imaging finished with errors."
    echo "The map file was preserved."
    echo
    echo "You can resume the operation later using:"
    echo "$map"
fi

exit "$status"

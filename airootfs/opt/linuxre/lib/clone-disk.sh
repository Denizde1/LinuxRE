#!/usr/bin/env bash

set -uo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Disk cloning must be run as root." >&2
    exit 1
fi

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

source_size="$(blockdev --getsize64 "$source" 2>/dev/null || lsblk -dnbo SIZE "$source" 2>/dev/null || echo 0)"
target_size="$(blockdev --getsize64 "$target" 2>/dev/null || lsblk -dnbo SIZE "$target" 2>/dev/null || echo 0)"
source_id="$(lsblk -dnno MODEL,SERIAL,WWN "$source" 2>/dev/null | awk 'NF {print; exit}')"
target_id="$(lsblk -dnno MODEL,SERIAL,WWN "$target" 2>/dev/null | awk 'NF {print; exit}')"

if (( source_size > 0 )) && (( target_size > 0 )) && (( source_size > target_size )); then
    echo
    echo "Error: The target device is smaller than the source device."
    echo "Source size: $source_size bytes"
    echo "Target size: $target_size bytes"
    exit 1
fi

echo
echo "Source: $source"
echo "Source model/serial: ${source_id:-unknown}"
echo "Target: $target"
echo "Target model/serial: ${target_id:-unknown}"
echo "Source size: $source_size bytes"
echo "Target size: $target_size bytes"
echo

echo "========================================"
echo "             WARNING!"
echo "========================================"
echo
echo "All existing data on the target device"
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
    echo "If you cloned a disk to larger disk, you should extend the partition. You can use GParted, cfdisk etc."
else
    echo "Cloning finished with errors."
    echo "The map file was preserved:"
    echo "$map"
fi

exit "$status"

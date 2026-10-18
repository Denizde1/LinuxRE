#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/imaging.sh

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

if imaging_devices_overlap "$source" "$target"; then
    echo
    echo "Error: Source and target are the same device or one contains the other."
    exit 1
else
    overlap_status=$?
    if (( overlap_status == 2 )); then
        echo "Error: Unable to inspect the source and target device relationships."
        exit 1
    fi
fi

if [[ "$(lsblk -dnro TYPE "$source" 2>/dev/null)" != "disk" ||
      "$(lsblk -dnro TYPE "$target" 2>/dev/null)" != "disk" ]]; then
    echo
    echo "Error: Disk cloning requires both source and target to be whole disks."
    exit 1
fi

if imaging_device_is_mounted "$target"; then
    echo
    echo "Error: Target disk or one of its partitions is mounted."
    echo "Unmount the target and all child filesystems before cloning."
    exit 1
else
    target_status=$?
    if (( target_status == 2 )); then
        echo "Error: Unable to inspect target disk mount state."
        exit 1
    fi
fi

if imaging_device_is_mounted "$source"; then
    echo
    echo "WARNING: Source disk or one of its partitions is mounted; the clone may be inconsistent."
    read -rp "Continue anyway? [y/N]: " mounted_confirm
    if [[ ! "$mounted_confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
else
    source_status=$?
    if (( source_status == 2 )); then
        echo "Error: Unable to inspect source disk mount state."
        exit 1
    fi
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

read -rp "Map file path on persistent storage (needed to resume): " map_path
map="$(imaging_map_path clone "$source" "$target" "$map_path")" || exit 1
map_dir="$(dirname "$map")"
if [[ ! -d "$map_dir" || ! -w "$map_dir" ]]; then
    echo
    echo "Error: Map file directory does not exist or is not writable: $map_dir"
    exit 1
fi

echo
echo "Source: $source"
echo "Source model/serial: ${source_id:-unknown}"
echo "Target: $target"
echo "Target model/serial: ${target_id:-unknown}"
echo "Source size: $source_size bytes"
echo "Target size: $target_size bytes"
echo "Map: $map"
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

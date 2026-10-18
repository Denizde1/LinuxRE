#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/imaging.sh

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Image restore must be run as root." >&2
    exit 1
fi

echo "========================================"
echo "       Restore System Image"
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
read -rp "System image path (example: /mnt/backup/system.img): " image
read -rp "Target disk or partition (example: /dev/nvme0n1): " target

if [[ -L "$image" || ! -f "$image" ]]; then
    echo
    echo "Error: Image must be an existing regular, non-symlink file."
    exit 1
fi

if [[ ! -b "$target" ]]; then
    echo
    echo "Error: Target device does not exist."
    exit 1
fi

if imaging_device_is_mounted "$target"; then
    echo
    echo "Error: Target device or one of its partitions is mounted."
    echo "Unmount the target and all child filesystems before restoring an image."
    exit 1
else
    target_status=$?
    if (( target_status == 2 )); then
        echo "Error: Unable to inspect target device mount state."
        exit 1
    fi
fi

map="$(imaging_map_path restore "$image" "$target")" || exit 1
map_dir="$(dirname "$map")"
if [[ ! -d "$map_dir" || ! -w "$map_dir" ]]; then
    echo "Error: Map file directory does not exist or is not writable: $map_dir"
    exit 1
fi

image_size="$(stat -c '%s' "$image" 2>/dev/null || echo 0)"
target_size="$(blockdev --getsize64 "$target" 2>/dev/null || lsblk -dnbo SIZE "$target" 2>/dev/null || echo 0)"
target_id="$(lsblk -dnno MODEL,SERIAL,WWN "$target" 2>/dev/null | awk 'NF {print; exit}')"

if (( image_size > 0 )) && (( target_size > 0 )) && (( image_size > target_size )); then
    echo
    echo "Error: The target device is smaller than the image."
    echo "Image size: $image_size bytes"
    echo "Target size: $target_size bytes"
    exit 1
fi

echo
echo "Image : $image"
echo "Target: $target"
echo "Target model/serial: ${target_id:-unknown}"
echo "Image size: $image_size bytes"
echo "Target size: $target_size bytes"
echo
echo "WARNING!"
echo "All existing data on the target may be overwritten."
echo

read -rp "Type RESTORE to continue: " confirm

if [[ "$confirm" != "RESTORE" ]]; then
    echo "Cancelled."
    exit 0
fi

echo
echo "Restoring system image..."
echo

ddrescue --force "$image" "$target" "$map"

status=$?

echo

if [[ $status -eq 0 ]]; then
    echo "System image restored successfully."
else
    echo "Restore finished with errors."
    echo "The restore map was preserved:"
    echo "$map"
fi

exit "$status"

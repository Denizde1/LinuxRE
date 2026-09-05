#!/usr/bin/env bash

set -uo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Disk imaging must be run as root." >&2
    exit 1
fi

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
destination_dir="$(dirname "$image")"

echo
source_size="$(blockdev --getsize64 "$source" 2>/dev/null || lsblk -dnbo SIZE "$source" 2>/dev/null || echo 0)"
source_id="$(lsblk -dnno MODEL,SERIAL,WWN "$source" 2>/dev/null | awk 'NF {print; exit}')"

echo "Source : $source"
echo "Model  : ${source_id:-unknown}"
echo "Size   : ${source_size:-0} bytes"
echo "Image  : $image"
echo "Map    : $map"
echo

if findmnt -rn -S "$source" >/dev/null 2>&1; then
    echo "WARNING: Source device appears to be mounted."
    echo
    findmnt -rn -S "$source"
    echo
    read -rp "Continue anyway? [y/N]: " mounted_confirm

    if [[ ! "$mounted_confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

if [[ -e "$image" ]]; then
    echo "WARNING: Destination image already exists."
    echo
    read -rp "Overwrite it? [y/N]: " overwrite

    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

if [[ "$source" == "$image" ]]; then
    echo
    echo "Error: Source and destination cannot be the same."
    exit 1
fi

mkdir -p "$destination_dir" || {
    echo "Error: Could not access destination directory."
    exit 1
}

echo
echo "Select imaging mode:"
echo
echo "  1) Fast       - First pass only"
echo "  2) Balanced   - First pass + 3 retries"
echo "  3) Recovery   - First pass + 5 retries"
echo "  4) Resume     - Continue using existing map file"
echo

read -rp "Select mode [1-4]: " mode

case "$mode" in
    1)
        echo
        echo "Mode: Fast"
        echo "Starting first pass..."
        echo

        ddrescue --force --no-scrape \
            "$source" "$image" "$map"

        status=$?
        ;;

    2)
        echo
        echo "Mode: Balanced"
        echo "Starting first pass..."
        echo

        ddrescue --force --no-scrape \
            "$source" "$image" "$map"

        first_status=$?

        echo
        echo "First pass completed."
        echo

        read -rp "Retry failed areas 3 times? [Y/n]: " retry_confirm

        if [[ "$retry_confirm" =~ ^[Nn]$ ]]; then
            status=$first_status
        else
            echo
            echo "Starting recovery pass (-r3)..."
            echo

            ddrescue --force --retry-passes=3 \
                "$source" "$image" "$map"

            status=$?
        fi
        ;;

    3)
        echo
        echo "Mode: Recovery"
        echo "Starting first pass..."
        echo

        ddrescue --force --no-scrape \
            "$source" "$image" "$map"

        first_status=$?

        echo
        echo "First pass completed."
        echo

        read -rp "Retry failed areas 5 times? [Y/n]: " retry_confirm

        if [[ "$retry_confirm" =~ ^[Nn]$ ]]; then
            status=$first_status
        else
            echo
            echo "Starting recovery pass (-r5)..."
            echo

            ddrescue --force --retry-passes=5 \
                "$source" "$image" "$map"

            status=$?
        fi
        ;;

    4)
        if [[ ! -f "$map" ]]; then
            echo
            echo "Error: No map file exists."
            echo "Cannot resume without:"
            echo "$map"
            exit 1
        fi

        echo
        echo "Mode: Resume"
        echo "Using existing map file:"
        echo "$map"
        echo

        ddrescue --force \
            "$source" "$image" "$map"

        status=$?
        ;;

    *)
        echo
        echo "Error: Invalid mode."
        exit 1
        ;;
esac

echo

if [[ $status -eq 0 ]]; then
    echo "========================================"
    echo "       Imaging completed successfully"
    echo "========================================"
    echo
    echo "Image: $image"
    echo "Map:   $map"
else
    echo "========================================"
    echo "       Imaging finished with errors"
    echo "========================================"
    echo
    echo "The map file was preserved."
    echo
    echo "You can resume later with:"
    echo "$map"
fi

echo

exit "$status"

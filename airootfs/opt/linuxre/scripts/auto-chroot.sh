#!/usr/bin/env bash

set -uo pipefail

LIB="/opt/linuxre/lib/chroot-common.sh"

if [[ ! -f "$LIB" ]]; then
    echo "[ERROR] LinuxRE chroot library was not found:"
    echo "        $LIB"
    exit 1
fi

# shellcheck disable=SC1091
source "$LIB"

# --------------------------------------------------
# Root check
# --------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    die "This tool must be run as root."
    exit 1
fi

# --------------------------------------------------
# Required commands
# --------------------------------------------------

for cmd in \
    lsblk \
    blkid \
    mount \
    umount \
    mountpoint \
    awk \
    sed \
    arch-chroot
do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "$cmd was not found."
        exit 1
    fi
done

mkdir -p "$MNT"

# --------------------------------------------------
# Find Linux root candidates
# --------------------------------------------------

log "Scanning for Linux filesystems..."

if ! detect_root_filesystems; then
    echo
    echo "No supported Linux filesystems were found."
    echo
    lsblk -f
    echo
    die "Linux root filesystem not found."
    exit 1
fi

# --------------------------------------------------
# Display candidates
# --------------------------------------------------

echo
echo "Detected Linux filesystems:"
echo

for i in "${!ROOTS[@]}"; do
    dev="${ROOTS[$i]}"

    echo "[$((i + 1))] $dev"

    lsblk -no \
        SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS \
        "$dev" |
        sed 's/^/    /'

    echo
done

# --------------------------------------------------
# Select root filesystem
# --------------------------------------------------

while true; do
    read -rp \
        "Which system should be chrooted into? [1-${#ROOTS[@]}]: " \
        choice

    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
        break
    fi

    echo "Invalid selection."
done

ROOT_DEV="${ROOTS[$((choice - 1))]}"

if ! set_root "$ROOT_DEV"; then
    die "Unable to determine the filesystem type of $ROOT_DEV."
    exit 1
fi

echo
log "Selected root: $ROOT_DEV"
log "Filesystem: $ROOT_FSTYPE"

# --------------------------------------------------
# Detect Btrfs root subvolume
# --------------------------------------------------

if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    log "Searching for the Btrfs root subvolume..."

    if ! detect_btrfs_subvolume; then
        die "Unable to automatically detect the Btrfs root subvolume."
        exit 1
    fi

    log "Root subvolume: $ROOT_SUBVOL"
fi

# --------------------------------------------------
# Mount target
# --------------------------------------------------

log "Preparing target system..."

if ! prepare_target; then
    die "Failed to prepare the target system."
    exit 1
fi

ok "Target system mounted."

# --------------------------------------------------
# Detect operating system
# --------------------------------------------------

PRETTY_NAME="Unknown"

if [[ -f "$MNT/etc/os-release" ]]; then
    # shellcheck disable=SC1091
    . "$MNT/etc/os-release"

    PRETTY_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
else
    warn "/etc/os-release was not found."
fi

# --------------------------------------------------
# Final confirmation
# --------------------------------------------------

echo
echo "========================================"
echo "          LinuxRE Auto Chroot"
echo "========================================"
echo
echo "System : $PRETTY_NAME"
echo "Root   : $ROOT_DEV"
echo "FS     : $ROOT_FSTYPE"

if [[ -n "$ROOT_SUBVOL" ]]; then
    echo "Subvol : $ROOT_SUBVOL"
fi

echo "ESP    : $ESP_DEV"
echo "ESP FS : ${ESP_FSTYPE:-Unknown}"
echo "ESP    : $ESP_MOUNT"
echo
echo "Mount layout:"
echo "  Root → $MNT"
echo "  ESP  → $MNT$ESP_MOUNT"
echo
echo "========================================"
echo

read -rp "Continue? [Y/n]: " confirm
confirm="${confirm:-Y}"

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    cleanup
    exit 0
fi

# --------------------------------------------------
# Enter chroot
# --------------------------------------------------

echo
echo "========================================"
echo "       Entering Arch Linux chroot"
echo "========================================"
echo

arch-chroot "$MNT"
CHROOT_STATUS=$?

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

echo
echo "Exited chroot."

if (( CHROOT_STATUS != 0 )); then
    warn "arch-chroot exited with status $CHROOT_STATUS."
else
    ok "arch-chroot exited successfully."
fi

echo
echo "Cleaning up mounts..."

cleanup

exit "$CHROOT_STATUS"

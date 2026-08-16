#!/usr/bin/env bash

# LinuxRE shared chroot/target-system helpers.
# This file is intentionally independent from the interactive UI.

set -uo pipefail

MNT="${MNT:-/mnt}"
TMP="${TMP:-$MNT/.linuxre}"

ROOT_DEV=""
ROOT_UUID=""
ROOT_FSTYPE=""
ROOT_SUBVOL=""

ESP_DEV=""
ESP_FSTYPE=""
ESP_MOUNT=""

ROOTS=()

# --------------------------------------------------
# Logging
# --------------------------------------------------

log() {
    printf '[*] %s\n' "$*"
}

ok() {
    printf '[OK] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    cleanup
    return 1
}

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

cleanup() {

    if [[ -d "$MNT" ]]; then
        umount -R "$MNT" 2>/dev/null || true
    fi

    rm -rf "$TMP" 2>/dev/null || true
}

# --------------------------------------------------
# Detect Linux root candidates
# --------------------------------------------------

detect_root_filesystems() {

    ROOTS=()

    while read -r dev fstype type; do

        [[ "$type" == "part" ]] || continue
        [[ -n "$fstype" ]] || continue

        case "$fstype" in
            btrfs|ext4|xfs|f2fs)
                ROOTS+=("$dev")
                ;;
        esac

    done < <(
        lsblk -rpno NAME,FSTYPE,TYPE
    )

    ((${#ROOTS[@]} > 0))
}

# --------------------------------------------------
# Set root filesystem
# --------------------------------------------------

set_root() {

    local dev="$1"

    [[ -b "$dev" ]] || return 1

    ROOT_DEV="$dev"

    ROOT_UUID="$(
        blkid -o value -s UUID "$ROOT_DEV" 2>/dev/null || true
    )"

    ROOT_FSTYPE="$(
        blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null || true
    )"

    [[ -n "$ROOT_FSTYPE" ]]
}

# --------------------------------------------------
# Detect Btrfs root subvolume
# --------------------------------------------------

detect_btrfs_subvolume() {

    [[ "$ROOT_FSTYPE" == "btrfs" ]] || return 0

    command -v btrfs >/dev/null 2>&1 || {
        warn "btrfs command was not found."
        return 1
    }

    mkdir -p "$TMP"

    if ! mount "$ROOT_DEV" "$TMP"; then
        return 1
    fi

    ROOT_SUBVOL=""

    # Common Arch/Linux layouts.
    for candidate in \
        @ \
        root \
        ROOT \
        @root
    do

        if [[ -f "$TMP/$candidate/etc/os-release" ]]; then
            ROOT_SUBVOL="$candidate"
            break
        fi

    done

    # Search all subvolumes if common names failed.
    if [[ -z "$ROOT_SUBVOL" ]]; then

        while IFS= read -r subvol_path; do

            [[ -n "$subvol_path" ]] || continue

            if [[ -f "$TMP/$subvol_path/etc/os-release" ]]; then
                ROOT_SUBVOL="$subvol_path"
                break
            fi

        done < <(
            btrfs subvolume list "$TMP" |
            sed -n 's/.* path //p'
        )

    fi

    umount "$TMP" 2>/dev/null || true

    [[ -n "$ROOT_SUBVOL" ]]
}

# --------------------------------------------------
# Mount root filesystem
# --------------------------------------------------

mount_root() {

    mkdir -p "$MNT"

    case "$ROOT_FSTYPE" in

        btrfs)

            [[ -n "$ROOT_SUBVOL" ]] || return 1

            mount \
                -o "subvol=$ROOT_SUBVOL" \
                "$ROOT_DEV" \
                "$MNT"

            ;;

        ext4|xfs|f2fs)

            mount "$ROOT_DEV" "$MNT"

            ;;

        *)

            warn "Unsupported filesystem: $ROOT_FSTYPE"
            return 1

            ;;

    esac
}

# --------------------------------------------------
# Detect ESP
# --------------------------------------------------

detect_esp() {

    local fstab="$MNT/etc/fstab"

    ESP_DEV=""

    # --------------------------------------------------
    # Method 1: fstab /boot
    # --------------------------------------------------

    if [[ -f "$fstab" ]]; then

        while read -r spec mountpoint options; do

            [[ "$mountpoint" == "/boot" ]] || continue
            [[ -n "$spec" ]] || continue

            case "$spec" in

                /dev/*)

                    if [[ -b "$spec" ]]; then
                        ESP_DEV="$spec"
                    fi

                    ;;

                UUID=*)

                    ESP_DEV="$(
                        blkid \
                            -t "UUID=${spec#UUID=}" \
                            -o device \
                            2>/dev/null || true
                    )"

                    ;;

                PARTUUID=*)

                    ESP_DEV="$(
                        blkid \
                            -t "PARTUUID=${spec#PARTUUID=}" \
                            -o device \
                            2>/dev/null || true
                    )"

                    ;;

                LABEL=*)

                    ESP_DEV="$(
                        blkid \
                            -t "LABEL=${spec#LABEL=}" \
                            -o device \
                            2>/dev/null || true
                    )"

                    ;;

                PARTLABEL=*)

                    ESP_DEV="$(
                        blkid \
                            -t "PARTLABEL=${spec#PARTLABEL=}" \
                            -o device \
                            2>/dev/null || true
                    )"

                    ;;

            esac

            [[ -n "$ESP_DEV" ]] && break

        done < <(
            awk '
                /^[[:space:]]*#/ { next }
                NF >= 2 {
                    print $1, $2, $4
                }
            ' "$fstab"
        )

    fi

    # --------------------------------------------------
    # Method 2: GPT ESP type
    # --------------------------------------------------

    if [[ -z "$ESP_DEV" ]]; then

        ESP_DEV="$(
            lsblk -rpno NAME,PARTTYPE |
            awk '
                tolower($2) ==
                "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {
                    print $1
                    exit
                }
            '
        )"

    fi

    [[ -n "$ESP_DEV" ]] || return 1

    [[ -b "$ESP_DEV" ]] || return 1

    ESP_FSTYPE="$(
        blkid \
            -o value \
            -s TYPE \
            "$ESP_DEV" \
            2>/dev/null || true
    )"

    case "$ESP_FSTYPE" in
        vfat|fat|fat16|fat32)
            ;;
        *)
            warn "ESP $ESP_DEV has filesystem type '$ESP_FSTYPE'."
            ;;
    esac

    return 0
}

# --------------------------------------------------
# Detect ESP mount point
# --------------------------------------------------

detect_esp_mount() {

    ESP_MOUNT=""

    if [[ -f "$MNT/etc/fstab" ]]; then

        if awk '
            /^[[:space:]]*#/ { next }
            $2 == "/efi" { found=1 }
            END { exit !found }
        ' "$MNT/etc/fstab"; then

            ESP_MOUNT="/efi"

        elif awk '
            /^[[:space:]]*#/ { next }
            $2 == "/boot" { found=1 }
            END { exit !found }
        ' "$MNT/etc/fstab"; then

            ESP_MOUNT="/boot"

        fi

    fi

    # Default to /boot for Arch installations.
    if [[ -z "$ESP_MOUNT" ]]; then
        ESP_MOUNT="/boot"
    fi
}

# --------------------------------------------------
# Mount ESP
# --------------------------------------------------

mount_esp() {

    [[ -n "$ESP_DEV" ]] || return 1
    [[ -n "$ESP_MOUNT" ]] || return 1

    mkdir -p "$MNT$ESP_MOUNT"

    if mountpoint -q "$MNT$ESP_MOUNT"; then
        return 0
    fi

    mount "$ESP_DEV" "$MNT$ESP_MOUNT"
}

# --------------------------------------------------
# Prepare complete target
# --------------------------------------------------

prepare_target() {

    mkdir -p "$MNT"

    if [[ "$ROOT_FSTYPE" == "btrfs" &&
          -z "$ROOT_SUBVOL" ]]; then

        detect_btrfs_subvolume || {
            warn "Unable to detect Btrfs root subvolume."
            return 1
        }

    fi

    mount_root || {
        warn "Failed to mount root filesystem."
        return 1
    }

    if [[ ! -f "$MNT/etc/os-release" ]]; then
        warn "Target does not appear to contain a Linux installation."
        return 1
    fi

    detect_esp || {
        warn "EFI System Partition was not found."
        return 1
    }

    detect_esp_mount

    mount_esp || {
        warn "Failed to mount ESP at $MNT$ESP_MOUNT."
        return 1
    }

    return 0
}


# --------------------------------------------------
# Prepare chroot environment
# --------------------------------------------------

prepare_chroot() {
    [[ -d "$MNT/etc" ]] || return 1

    # arch-chroot handles /dev, /proc, /sys and /run.
    # We only need to make DNS available inside the target.

    if [[ -e /etc/resolv.conf ]]; then
        rm -f "$MNT/etc/resolv.conf"

        if ! cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"; then
            warn "Failed to copy DNS configuration."
            return 1
        fi
    fi

    return 0
}


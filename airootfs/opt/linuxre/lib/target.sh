#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/common.sh

# ==================================================
# Target state
# ==================================================

ROOT_DEV=""
ROOT_UUID=""
ROOT_FSTYPE=""
ROOT_SUBVOL=""
ESP_DEV=""
ESP_UUID=""
ESP_FSTYPE=""
ESP_MOUNT=""

ROOTS=()

# ==================================================
# Root filesystem detection
# ==================================================

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

    if ((${#ROOTS[@]} == 0)); then
        return 1
    fi

    return 0
}

# ==================================================
# Root filesystem information
# ==================================================

set_root() {
    local dev="$1"

    if [[ ! -b "$dev" ]]; then
        warn "Invalid block device: $dev"
        return 1
    fi

    ROOT_DEV="$dev"

    ROOT_UUID="$(
        blkid -o value -s UUID "$dev" 2>/dev/null || true
    )"

    ROOT_FSTYPE="$(
        blkid -o value -s TYPE "$dev" 2>/dev/null || true
    )"

    if [[ -z "$ROOT_UUID" ]]; then
        warn "Unable to determine UUID for $dev."
        return 1
    fi

    if [[ -z "$ROOT_FSTYPE" ]]; then
        warn "Unable to determine filesystem type for $dev."
        return 1
    fi

    return 0
}

# ==================================================
# Btrfs root subvolume
# ==================================================

detect_btrfs_subvolume() {
    [[ "$ROOT_FSTYPE" == "btrfs" ]] || return 0

    require_commands btrfs mount umount || return 1

    mkdir -p "$TMP"

    log "Inspecting Btrfs subvolumes..."

    if ! mount "$ROOT_DEV" "$TMP"; then
        warn "Failed to temporarily mount Btrfs filesystem."
        return 1
    fi

    ROOT_SUBVOL=""

    # --------------------------------------------------
    # Check top-level subvolume (ID 5)
    # --------------------------------------------------

    # The top-level Btrfs subvolume has ID 5 and is not
    # normally listed by `btrfs subvolume list`.

    if [[ -f "$TMP/etc/os-release" ]]; then
        ROOT_SUBVOL="5"
    else
        # --------------------------------------------------
        # Check child subvolumes
        # --------------------------------------------------

        while IFS= read -r subvol; do
            [[ -n "$subvol" ]] || continue

            if [[ -f "$TMP/$subvol/etc/os-release" ]]; then
                ROOT_SUBVOL="$subvol"
                break
            fi
        done < <(
            btrfs subvolume list "$TMP" |
                sed -n 's/.* path //p'
        )
    fi

    umount "$TMP" 2>/dev/null || true

    if [[ -z "$ROOT_SUBVOL" ]]; then
        warn "Unable to determine Btrfs root subvolume."
        return 1
    fi

    if [[ "$ROOT_SUBVOL" == "5" ]]; then
        log "Btrfs root: top-level subvolume (ID 5)"
    else
        log "Btrfs root subvolume: $ROOT_SUBVOL"
    fi

    return 0
}

# ==================================================
# Mount root
# ==================================================

mount_root() {
    mkdir -p "$MNT"

    if mountpoint -q "$MNT"; then
        return 0
    fi

    case "$ROOT_FSTYPE" in
        btrfs)
            if [[ -z "$ROOT_SUBVOL" ]]; then
                warn "Btrfs root subvolume has not been detected."
                return 1
            fi

            # Btrfs subvolume ID 5 must be mounted using
            # subvolid=5. Other subvolumes are mounted
            # using their path/name.

            if [[ "$ROOT_SUBVOL" == "5" ]]; then
                log "Mounting Btrfs top-level subvolume (ID 5)..."

                if ! mount \
                    -o subvolid=5 \
                    "$ROOT_DEV" \
                    "$MNT"; then
                    warn "Failed to mount Btrfs root subvolume."
                    return 1
                fi
            else
                log "Mounting Btrfs subvolume: $ROOT_SUBVOL"

                if ! mount \
                    -o "subvol=$ROOT_SUBVOL" \
                    "$ROOT_DEV" \
                    "$MNT"; then
                    warn "Failed to mount Btrfs root subvolume."
                    return 1
                fi
            fi
            ;;

        ext4|xfs|f2fs)
            if ! mount "$ROOT_DEV" "$MNT"; then
                warn "Failed to mount root filesystem."
                return 1
            fi
            ;;

        *)
            warn "Unsupported root filesystem: $ROOT_FSTYPE"
            return 1
            ;;
    esac

    return 0
}

# ==================================================
# EFI System Partition detection
# ==================================================

detect_esp() {
    ESP_DEV=""
    ESP_UUID=""
    ESP_FSTYPE=""

    local fstab="$MNT/etc/fstab"

    # --------------------------------------------------
    # Method 1: target fstab
    # --------------------------------------------------

    if [[ -f "$fstab" ]]; then
        while read -r spec mountpoint _; do
            [[ "$mountpoint" == "/boot" ||
               "$mountpoint" == "/efi" ]] || continue

            case "$spec" in
                UUID=*)
                    ESP_DEV="$(
                        blkid -t "UUID=${spec#UUID=}" \
                            -o device 2>/dev/null || true
                    )"
                    ;;

                PARTUUID=*)
                    ESP_DEV="$(
                        blkid -t "PARTUUID=${spec#PARTUUID=}" \
                            -o device 2>/dev/null || true
                    )"
                    ;;

                LABEL=*)
                    ESP_DEV="$(
                        blkid -t "LABEL=${spec#LABEL=}" \
                            -o device 2>/dev/null || true
                    )"
                    ;;

                PARTLABEL=*)
                    ESP_DEV="$(
                        blkid -t "PARTLABEL=${spec#PARTLABEL=}" \
                            -o device 2>/dev/null || true
                    )"
                    ;;

                /dev/*)
                    if [[ -b "$spec" ]]; then
                        ESP_DEV="$spec"
                    fi
                    ;;
            esac

            [[ -n "$ESP_DEV" ]] && break

        done < <(
            awk '
                /^[[:space:]]*#/ { next }
                NF >= 2 { print $1, $2 }
            ' "$fstab"
        )
    fi

    # --------------------------------------------------
    # Method 2: GPT ESP partition type
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

    if [[ -z "$ESP_DEV" ]]; then
        warn "EFI System Partition not found."
        return 1
    fi

    # shellcheck disable=SC2034
    ESP_UUID="$(
        blkid -o value -s UUID "$ESP_DEV" 2>/dev/null || true
    )"

    ESP_FSTYPE="$(
        blkid -o value -s TYPE "$ESP_DEV" 2>/dev/null || true
    )"

    case "$ESP_FSTYPE" in
        vfat|fat|fat16|fat32)
            ;;

        *)
            warn "ESP filesystem type is '$ESP_FSTYPE'."
            return 1
            ;;
    esac

    return 0
}

# ==================================================
# ESP mount point
# ==================================================

detect_esp_mount() {
    ESP_MOUNT=""

    if [[ -f "$MNT/etc/fstab" ]]; then

        if awk '
            /^[[:space:]]*#/ { next }
            $2 == "/efi" { found=1 }
            END { exit !found }
        ' "$MNT/etc/fstab"; then
            ESP_MOUNT="/efi"
            return 0
        fi

        if awk '
            /^[[:space:]]*#/ { next }
            $2 == "/boot" { found=1 }
            END { exit !found }
        ' "$MNT/etc/fstab"; then
            ESP_MOUNT="/boot"
            return 0
        fi
    fi

    # Arch commonly uses /boot.
    ESP_MOUNT="/boot"

    return 0
}

# ==================================================
# Mount ESP
# ==================================================

mount_esp() {
    [[ -n "$ESP_DEV" ]] || {
        warn "ESP device is not set."
        return 1
    }

    [[ -n "$ESP_MOUNT" ]] || {
        warn "ESP mount point is not set."
        return 1
    }

    mkdir -p "$MNT$ESP_MOUNT"

    if mountpoint -q "$MNT$ESP_MOUNT"; then
        return 0
    fi

    log "Mounting ESP: $ESP_DEV -> $ESP_MOUNT"

    if ! mount "$ESP_DEV" "$MNT$ESP_MOUNT"; then
        warn "Failed to mount ESP."
        return 1
    fi

    if ! mountpoint -q "$MNT$ESP_MOUNT"; then
        warn "ESP mount verification failed."
        return 1
    fi

    return 0
}

# ==================================================
# Prepare target
# ==================================================

prepare_target() {
    mkdir -p "$MNT"

    if [[ -z "$ROOT_DEV" ]]; then
        warn "Root device has not been selected."
        return 1
    fi

    if [[ "$ROOT_FSTYPE" == "btrfs" &&
          -z "$ROOT_SUBVOL" ]]; then
        detect_btrfs_subvolume || return 1
    fi

    mount_root || {
        warn "Failed to mount root filesystem."
        return 1
    }

    if [[ ! -f "$MNT/etc/os-release" ]]; then
        warn "Target does not appear to contain a Linux installation."
        return 1
    fi

    detect_esp || return 1

    detect_esp_mount

    mount_esp || return 1

    ok "Target prepared."

    return 0
}
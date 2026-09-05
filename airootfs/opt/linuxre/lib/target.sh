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

LUKS_DEVICES=()
OPENED_LUKS=()

LVM_VGS=()
LVM_LVS=()
ACTIVATED_VGS=()

# Track mounts created by LinuxRE.
TARGET_ROOT_MOUNTED=0
TARGET_ESP_MOUNTED=0

# ==================================================
# Supported filesystems
# ==================================================

is_supported_root_fs() {
    case "$1" in
        btrfs|ext4|xfs|f2fs)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==================================================
# Command requirements
# ==================================================

require_target_commands() {
    require_commands \
        lsblk \
        blkid \
        findmnt \
        mount \
        umount \
        mountpoint \
        awk \
        sed \
        sort \
        grep \
        head \
        || return 1

    return 0
}

# ==================================================
# Device helpers
# ==================================================

device_exists() {
    [[ -b "$1" ]]
}

device_fstype() {
    blkid -o value -s TYPE "$1" 2>/dev/null || true
}

device_uuid() {
    blkid -o value -s UUID "$1" 2>/dev/null || true
}

device_partuuid() {
    blkid -o value -s PARTUUID "$1" 2>/dev/null || true
}

device_parttype() {
    lsblk -dnro PARTTYPE "$1" 2>/dev/null || true
}

device_label() {
    blkid -o value -s LABEL "$1" 2>/dev/null || true
}

is_mounted_device() {
    findmnt -rn -S "$1" >/dev/null 2>&1
}

is_mounted_path() {
    mountpoint -q "$1"
}

# ==================================================
# LUKS detection
# ==================================================

detect_luks_devices() {
    LUKS_DEVICES=()

    require_commands lsblk || return 1

    while read -r dev fstype type; do
        [[ -n "$dev" ]] || continue
        [[ -b "$dev" ]] || continue
        [[ "$fstype" == "crypto_LUKS" ]] || continue

        LUKS_DEVICES+=("$dev")
    done < <(
        lsblk -rpno NAME,FSTYPE,TYPE 2>/dev/null
    )

    if ((${#LUKS_DEVICES[@]} > 0)); then
        mapfile -t LUKS_DEVICES < <(
            printf '%s\n' "${LUKS_DEVICES[@]}" |
                sort -u
        )
    fi

    return 0
}

# ==================================================
# LUKS mapper
# ==================================================

luks_mapper_name() {
    local dev="$1"
    local uuid

    uuid="$(device_uuid "$dev")"

    [[ -n "$uuid" ]] || return 1

    printf 'linuxre-%s\n' "${uuid//-/}"
}

# ==================================================
# Unlock one LUKS device
# ==================================================

unlock_luks_device() {

    local dev="$1"
    local mapper_name
    local mapper
    local uuid

    if ! device_exists "$dev"; then
        warn "Invalid LUKS device: $dev"
        return 1
    fi

    require_commands cryptsetup blkid || return 1

    uuid="$(device_uuid "$dev")"

    if [[ -z "$uuid" ]]; then
        warn "Unable to determine LUKS UUID for $dev."
        return 1
    fi

    mapper_name="$(luks_mapper_name "$dev")" || {
        warn "Unable to determine mapper name for $dev."
        return 1
    }

    mapper="/dev/mapper/$mapper_name"

    # Already unlocked before LinuxRE touched it.
    if [[ -b "$mapper" ]]; then
        log "LUKS device already unlocked: $mapper"
        return 0
    fi

    log "Unlocking LUKS device: $dev"

    if ! cryptsetup luksOpen "$dev" "$mapper_name"; then
        warn "Failed to unlock LUKS device: $dev"
        return 1
    fi

    if [[ ! -b "$mapper" ]]; then
        warn "LUKS mapper device was not created: $mapper"
        return 1
    fi

    OPENED_LUKS+=("$mapper")

    ok "Unlocked: $mapper"
    return 0
}

# ==================================================
# Unlock LUKS devices
# ==================================================

unlock_luks() {
    detect_luks_devices || return 1

    if ((${#LUKS_DEVICES[@]} == 0)); then
        return 0
    fi

    log "Detected LUKS devices:"

    local i=1
    local dev

    for dev in "${LUKS_DEVICES[@]}"; do
        printf '  [%d] %s\n' "$i" "$dev"
        ((i++))
    done

    printf '\n'

    # Single-device fast path.
    if ((${#LUKS_DEVICES[@]} == 1)); then
        read -r -p \
            "Unlock detected LUKS device? [y/N]: " \
            answer

        case "${answer,,}" in
            y|yes)
                unlock_luks_device "${LUKS_DEVICES[0]}"
                ;;
            *)
                return 0
                ;;
        esac

        return $?
    fi

    echo "Options:"
    echo "  1-${#LUKS_DEVICES[@]}) Unlock selected device"
    echo "  a) Unlock all"
    echo "  s) Skip"
    echo

    local selection

    read -r -p "Selection: " selection

    case "${selection,,}" in
        a|all)
            local failed=0

            for dev in "${LUKS_DEVICES[@]}"; do
                unlock_luks_device "$dev" || failed=1
            done

            return "$failed"
            ;;

        s|skip|"")
            return 0
            ;;
    esac

    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        warn "Invalid selection."
        return 1
    fi

    if ((selection < 1 || selection > ${#LUKS_DEVICES[@]})); then
        warn "Selection out of range."
        return 1
    fi

    unlock_luks_device \
        "${LUKS_DEVICES[$((selection - 1))]}"
}

# ==================================================
# LVM detection
# ==================================================

detect_lvm() {
    LVM_VGS=()
    LVM_LVS=()

    require_commands vgs lvs || return 1

    while IFS= read -r vg; do
        [[ -n "$vg" ]] || continue
        LVM_VGS+=("$vg")
    done < <(
        vgs \
            --noheadings \
            --options vg_name \
            2>/dev/null |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
            sed '/^$/d' |
            sort -u
    )

    while IFS= read -r lv; do
        [[ -n "$lv" ]] || continue
        LVM_LVS+=("$lv")
    done < <(
        lvs \
            --noheadings \
            --options lv_path \
            2>/dev/null |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
            sed '/^$/d' |
            sort -u
    )

    return 0
}

# ==================================================
# Get active LVM volume groups
# ==================================================

get_active_vgs() {
    require_commands vgs || return 1

    vgs \
        --noheadings \
        --options vg_name,vg_active \
        2>/dev/null |
        awk '
            $2 == "active" {
                print $1
            }
        ' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
        sed '/^$/d' |
        sort -u

    return 0
}

# ==================================================
# LVM activation
# ==================================================

activate_lvm() {
    require_commands vgscan vgchange vgs lvs || return 1

    log "Scanning for LVM volume groups..."

    vgscan --mknodes >/dev/null 2>&1 || true

    local before_file
    local after_file
    local vg

    before_file="/tmp/linuxre-vgs-before.$$"
    after_file="/tmp/linuxre-vgs-after.$$"

    get_active_vgs > "$before_file"

    if ! vgchange --available y >/dev/null 2>&1; then
        warn "Failed to activate LVM volume groups."
        rm -f "$before_file" "$after_file"
        return 1
    fi

    get_active_vgs > "$after_file"

    while IFS= read -r vg; do
        [[ -n "$vg" ]] || continue

        if ! grep -Fxq "$vg" "$before_file"; then
            ACTIVATED_VGS+=("$vg")
        fi
    done < "$after_file"

    rm -f "$before_file" "$after_file"

    detect_lvm || return 1

    if ((${#LVM_VGS[@]} == 0)); then
        return 0
    fi

    log "Detected LVM volume groups:"

    for vg in "${LVM_VGS[@]}"; do
        printf '  %s\n' "$vg"
    done

    if ((${#LVM_LVS[@]} > 0)); then
        log "Detected logical volumes:"

        local lv

        for lv in "${LVM_LVS[@]}"; do
            printf '  %s\n' "$lv"
        done
    fi

    return 0
}

# ==================================================
# Add root candidate
# ==================================================

add_root_candidate() {
    local dev="$1"
    local fstype

    [[ -b "$dev" ]] || return 0

    fstype="$(device_fstype "$dev")"

    is_supported_root_fs "$fstype" || return 0

    ROOTS+=("$dev")
}

# ==================================================
# Root filesystem detection
# ==================================================

detect_root_filesystems() {
    ROOTS=()

    require_commands lsblk blkid || return 1

    local dev
    local fstype
    local type

    while read -r dev fstype type; do
        [[ -n "$dev" ]] || continue
        [[ -b "$dev" ]] || continue

        case "$type" in
            part|crypt|lvm)
                add_root_candidate "$dev"
                ;;
        esac
    done < <(
        lsblk -rpno NAME,FSTYPE,TYPE 2>/dev/null
    )

    # Explicitly inspect mappers opened by LinuxRE.
    local mapper

    for mapper in "${OPENED_LUKS[@]}"; do
        add_root_candidate "$mapper"
    done

    if ((${#ROOTS[@]} > 0)); then
        mapfile -t ROOTS < <(
            printf '%s\n' "${ROOTS[@]}" |
                sort -u
        )
    fi

    ((${#ROOTS[@]} > 0))
}

# ==================================================
# Check whether filesystem contains Linux
# ==================================================

looks_like_linux_root() {
    local dev="$1"
    local tmp="/run/linuxre-root-check"
    local existing_mount
    local result=1

    mkdir -p "$tmp"

    # Do not disturb an existing mount.
    if is_mounted_device "$dev"; then
        existing_mount="$(
            findmnt \
                -rn \
                -S "$dev" \
                -o TARGET \
                2>/dev/null |
                head -n1
        )"

        [[ -n "$existing_mount" ]] || return 1

        [[ -f "$existing_mount/etc/os-release" ]]
        return $?
    fi

    if ! mount -o ro "$dev" "$tmp" 2>/dev/null; then
        return 1
    fi

    if [[ -f "$tmp/etc/os-release" ]]; then
        result=0
    fi

    umount "$tmp" 2>/dev/null || true

    return "$result"
}

# ==================================================
# Root filesystem selection
# ==================================================

select_root_filesystem() {
    detect_root_filesystems || {
        warn "No supported root filesystems found."
        return 1
    }

    log "Detected root filesystem candidates:"

    local i=1
    local dev
    local fstype
    local marker

    for dev in "${ROOTS[@]}"; do
        fstype="$(device_fstype "$dev")"
        marker=""

        if looks_like_linux_root "$dev"; then
            marker=" [Linux root]"
        fi

        printf \
            '  [%d] %s (%s)%s\n' \
            "$i" \
            "$dev" \
            "$fstype" \
            "$marker"

        ((i++))
    done

    printf '\n'

    local selection

    if ((${#ROOTS[@]} == 1)); then
        selection=1
        log "Only one root filesystem candidate found."
    else
        read -r -p \
            "Select target root filesystem [1-${#ROOTS[@]}]: " \
            selection
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        warn "Invalid root filesystem selection."
        return 1
    fi

    if ((selection < 1 || selection > ${#ROOTS[@]})); then
        warn "Root filesystem selection out of range."
        return 1
    fi

    set_root "${ROOTS[$((selection - 1))]}"
}

# ==================================================
# Root filesystem information
# ==================================================

set_root() {
    local dev="$1"
    local fstype
    local uuid

    if ! device_exists "$dev"; then
        warn "Invalid block device: $dev"
        return 1
    fi

    fstype="$(device_fstype "$dev")"
    uuid="$(device_uuid "$dev")"

    if ! is_supported_root_fs "$fstype"; then
        warn "Unsupported root filesystem: ${fstype:-unknown}"
        return 1
    fi

    if [[ -z "$uuid" ]]; then
        warn "Unable to determine UUID for $dev."
        return 1
    fi

    ROOT_DEV="$dev"
    ROOT_UUID="$uuid"
    ROOT_FSTYPE="$fstype"
    ROOT_SUBVOL=""

    log "Selected root: $ROOT_DEV"
    log "Filesystem: $ROOT_FSTYPE"
    log "UUID: $ROOT_UUID"

    return 0
}

# ==================================================
# Btrfs root subvolume
# ==================================================

detect_btrfs_subvolume() {
    [[ "$ROOT_FSTYPE" == "btrfs" ]] || return 0

    require_commands btrfs mount umount || return 1

    local tmp="/run/linuxre-btrfs-inspect"
    local subvol

    mkdir -p "$tmp"

    ROOT_SUBVOL=""

    log "Inspecting Btrfs subvolumes..."

    if ! mount -o ro,subvolid=5 "$ROOT_DEV" "$tmp"; then
        warn "Failed to temporarily mount Btrfs top-level filesystem."
        return 1
    fi

    # Root itself is top-level.
    if [[ -f "$tmp/etc/os-release" ]]; then
        ROOT_SUBVOL="5"
    else
        while IFS= read -r subvol; do
            [[ -n "$subvol" ]] || continue

            if [[ -f "$tmp/$subvol/etc/os-release" ]]; then
                ROOT_SUBVOL="$subvol"
                break
            fi
        done < <(
            btrfs subvolume list "$tmp" 2>/dev/null |
                sed -n 's/^.* path //p'
        )
    fi

    umount "$tmp" 2>/dev/null || true

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
# Mount root filesystem
# ==================================================

mount_root() {

    mkdir -p "$MNT"

    if is_mounted_path "$MNT"; then
        log "Target root is already mounted: $MNT"
        return 0
    fi

    case "$ROOT_FSTYPE" in
        btrfs)
            if [[ -z "$ROOT_SUBVOL" ]]; then
                detect_btrfs_subvolume || return 1
            fi

            if [[ "$ROOT_SUBVOL" == "5" ]]; then
                log "Mounting Btrfs top-level subvolume (ID 5)..."

                if ! mount \
                    -o subvolid=5 \
                    "$ROOT_DEV" \
                    "$MNT"; then

                    warn "Failed to mount Btrfs root filesystem."
                    return 1
                fi
            else
                log "Mounting Btrfs subvolume: $ROOT_SUBVOL"

                if ! mount \
                    -o "subvol=$ROOT_SUBVOL" \
                    "$ROOT_DEV" \
                    "$MNT"; then

                    warn "Failed to mount Btrfs root filesystem."
                    return 1
                fi
            fi
            ;;

        ext4|xfs|f2fs)
            log "Mounting $ROOT_FSTYPE root filesystem..."

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

    # The mount succeeded, so cleanup must now know that
    # LinuxRE owns this mount.
    TARGET_ROOT_MOUNTED=1

    if ! is_mounted_path "$MNT"; then
        warn "Root filesystem mount verification failed."

        if umount "$MNT" 2>/dev/null; then
            TARGET_ROOT_MOUNTED=0
        else
            warn "Failed to clean up root filesystem mount."
        fi

        return 1
    fi

    return 0
}

# ==================================================
# Mount ESP
# ==================================================

# shellcheck disable=SC2329
mount_esp() {

    [[ -n "$ESP_DEV" ]] || {
        warn "ESP device is not set."
        return 1
    }

    [[ -n "$ESP_MOUNT" ]] || {
        warn "ESP mount point is not set."
        return 1
    }

    local target="$MNT$ESP_MOUNT"
    local existing_target
    local existing_source

    mkdir -p "$target"

    # Already mounted at target.
    if is_mounted_path "$target"; then
        existing_source="$(
            findmnt \
                -rn \
                -o SOURCE \
                --target "$target" \
                2>/dev/null |
                head -n1
        )"

        if [[ "$existing_source" == "$ESP_DEV" ]]; then
            log "ESP already mounted: $target"
            return 0
        fi

        warn "ESP mount point is already occupied: $target"
        return 1
    fi

    # ESP may already be mounted somewhere else.
    if is_mounted_device "$ESP_DEV"; then
        existing_target="$(
            findmnt \
                -rn \
                -S "$ESP_DEV" \
                -o TARGET \
                2>/dev/null |
                head -n1
        )"

        if [[ -n "$existing_target" ]]; then
            log "ESP is already mounted at: $existing_target"

            # If it is already under our target root, reuse it.
            if [[ "$existing_target" == "$target" ]]; then
                return 0
            fi

            warn "ESP is already mounted elsewhere: $existing_target"
            return 1
        fi
    fi

    log "Mounting ESP: $ESP_DEV -> $ESP_MOUNT"

    if ! mount "$ESP_DEV" "$target"; then
        warn "Failed to mount ESP."
        return 1
    fi

    # The mount succeeded, so cleanup must now know that
    # LinuxRE owns this mount.
    TARGET_ESP_MOUNTED=1

    if ! is_mounted_path "$target"; then
        warn "ESP mount verification failed."

        if umount "$target" 2>/dev/null; then
            TARGET_ESP_MOUNTED=0
        else
            warn "Failed to clean up ESP mount."
        fi

        return 1
    fi

    return 0
}

# ==================================================
# EFI System Partition helpers
# ==================================================

is_esp_partition() {
    local dev="$1"
    local parttype

    [[ -b "$dev" ]] || return 1

    parttype="$(device_parttype "$dev")"

    [[ "${parttype,,}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]
}

is_esp_filesystem() {
    local fstype="$1"

    case "$fstype" in
        vfat|fat|fat16|fat32)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==================================================
# Resolve fstab specification
# ==================================================

resolve_fstab_device() {
    local spec="$1"
    local dev=""

    case "$spec" in
        UUID=*)
            dev="$(blkid -t "UUID=${spec#UUID=}" -o device 2>/dev/null || true)"
            ;;

        PARTUUID=*)
            dev="$(blkid -t "PARTUUID=${spec#PARTUUID=}" -o device 2>/dev/null || true)"
            ;;

        LABEL=*)
            dev="$(blkid -t "LABEL=${spec#LABEL=}" -o device 2>/dev/null || true)"
            ;;

        PARTLABEL=*)
            dev="$(blkid -t "PARTLABEL=${spec#PARTLABEL=}" -o device 2>/dev/null || true)"
            ;;

        /dev/*)
            dev="$spec"
            ;;
    esac

    [[ -b "$dev" ]] || return 1

    printf '%s\n' "$dev"
}

# ==================================================
# EFI System Partition detection
# ==================================================

detect_esp() {
    ESP_DEV=""
    ESP_UUID=""
    ESP_FSTYPE=""

    local fstab="$MNT/etc/fstab"
    local spec
    local mountpoint
    local candidate
    local fstype

    # --------------------------------------------------
    # Method 1: target fstab
    # --------------------------------------------------

    if [[ -f "$fstab" ]]; then
        while read -r spec mountpoint _; do
            [[ "$mountpoint" == "/boot" ||
               "$mountpoint" == "/efi" ]] || continue

            candidate="$(resolve_fstab_device "$spec" 2>/dev/null || true)"

            [[ -n "$candidate" ]] || continue

            fstype="$(device_fstype "$candidate")"

            # A /boot filesystem may legitimately be ext4.
            # Do not mistake it for the ESP.
            if is_esp_partition "$candidate" &&
               is_esp_filesystem "$fstype"; then

                ESP_DEV="$candidate"
                break
            fi
        done < <(
            awk '
                /^[[:space:]]*#/ { next }
                NF >= 2 { print $1, $2, $3 }
            ' "$fstab"
        )
    fi

    # --------------------------------------------------
    # Method 2: GPT ESP partition type
    # --------------------------------------------------

    if [[ -z "$ESP_DEV" ]]; then
        while IFS= read -r candidate; do
            [[ -b "$candidate" ]] || continue

            if ! is_esp_partition "$candidate"; then
                continue
            fi

            fstype="$(device_fstype "$candidate")"

            if is_esp_filesystem "$fstype"; then
                ESP_DEV="$candidate"
                break
            fi
        done < <(
            lsblk -rpno NAME 2>/dev/null
        )
    fi

    # --------------------------------------------------
    # Method 3: vfat partition with ESP contents
    # --------------------------------------------------

    if [[ -z "$ESP_DEV" ]]; then
        while IFS= read -r candidate; do
            [[ -b "$candidate" ]] || continue

            fstype="$(device_fstype "$candidate")"

            is_esp_filesystem "$fstype" || continue

            # Only consider actual partitions.
            local type
            type="$(lsblk -dnro TYPE "$candidate" 2>/dev/null || true)"
            [[ "$type" == "part" ]] || continue

            if is_esp_partition "$candidate"; then
                ESP_DEV="$candidate"
                break
            fi
        done < <(
            lsblk -rpno NAME 2>/dev/null
        )
    fi

    if [[ -z "$ESP_DEV" || ! -b "$ESP_DEV" ]]; then
        warn "EFI System Partition not found."
        return 1
    fi

    ESP_UUID="$(device_uuid "$ESP_DEV")"
    ESP_FSTYPE="$(device_fstype "$ESP_DEV")"

    if ! is_esp_filesystem "$ESP_FSTYPE"; then
        warn "ESP filesystem type is '$ESP_FSTYPE'."
        return 1
    fi

    log "ESP: $ESP_DEV"
    log "ESP UUID: ${ESP_UUID:-unknown}"

    return 0
}

# ==================================================
# ESP mount point
# ==================================================

detect_esp_mount() {
    ESP_MOUNT=""

    local fstab="$MNT/etc/fstab"

    if [[ -f "$fstab" ]]; then
        if awk '
            /^[[:space:]]*#/ { next }
            $2 == "/efi" {
                found=1
            }
            END {
                exit !found
            }
        ' "$fstab"; then

            ESP_MOUNT="/efi"
            return 0
        fi

        if awk '
            /^[[:space:]]*#/ { next }
            $2 == "/boot" {
                found=1
            }
            END {
                exit !found
            }
        ' "$fstab"; then

            ESP_MOUNT="/boot"
            return 0
        fi
    fi

    # Arch/systemd-boot commonly uses /boot.
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

    local target="$MNT$ESP_MOUNT"
    local existing_target
    local existing_source

    mkdir -p "$target"

    # Already mounted at target.
    if is_mounted_path "$target"; then
        existing_source="$(
            findmnt \
                -rn \
                -o SOURCE \
                --target "$target" \
                2>/dev/null |
                head -n1
        )"

        if [[ "$existing_source" == "$ESP_DEV" ]]; then
            log "ESP already mounted: $target"
            return 0
        fi

        warn "ESP mount point is already occupied: $target"
        return 1
    fi

    # ESP may already be mounted somewhere else.
    if is_mounted_device "$ESP_DEV"; then
        existing_target="$(
            findmnt \
                -rn \
                -S "$ESP_DEV" \
                -o TARGET \
                2>/dev/null |
                head -n1
        )"

        if [[ -n "$existing_target" ]]; then
            log "ESP is already mounted at: $existing_target"

            # If it is already under our target root, reuse it.
            if [[ "$existing_target" == "$target" ]]; then
                return 0
            fi

            warn "ESP is already mounted elsewhere: $existing_target"
            return 1
        fi
    fi

    log "Mounting ESP: $ESP_DEV -> $ESP_MOUNT"

    if ! mount "$ESP_DEV" "$target"; then
        warn "Failed to mount ESP."
        return 1
    fi

    if ! is_mounted_path "$target"; then
        warn "ESP mount verification failed."
        return 1
    fi

    TARGET_ESP_MOUNTED=1

    return 0
}

# ==================================================
# Cleanup storage
# ==================================================

cleanup_target_storage() {
    local mapper
    local vg

    # --------------------------------------------------
    # Unmount ESP only if LinuxRE mounted it.
    # --------------------------------------------------

    if ((TARGET_ESP_MOUNTED)) &&
       [[ -n "$ESP_MOUNT" ]] &&
       is_mounted_path "$MNT$ESP_MOUNT"; then

        umount "$MNT$ESP_MOUNT" 2>/dev/null || true
    fi

    TARGET_ESP_MOUNTED=0

    # --------------------------------------------------
    # Unmount root only if LinuxRE mounted it.
    # --------------------------------------------------

    if ((TARGET_ROOT_MOUNTED)) &&
       is_mounted_path "$MNT"; then

        umount "$MNT" 2>/dev/null || true
    fi

    TARGET_ROOT_MOUNTED=0

    # --------------------------------------------------
    # Deactivate only VGs activated by LinuxRE.
    # --------------------------------------------------

    if command -v vgchange >/dev/null 2>&1; then
        for vg in "${ACTIVATED_VGS[@]}"; do
            [[ -n "$vg" ]] || continue

            log "Deactivating LVM volume group: $vg"

            vgchange \
                --available n \
                "$vg" \
                >/dev/null 2>&1 ||
                true
        done
    fi

    ACTIVATED_VGS=()

    # --------------------------------------------------
    # Close only LUKS devices opened by LinuxRE.
    # --------------------------------------------------

    if command -v cryptsetup >/dev/null 2>&1; then
        for mapper in "${OPENED_LUKS[@]}"; do
            [[ -b "$mapper" ]] || continue

            log "Closing LUKS mapper: $mapper"

            cryptsetup luksClose "$mapper" \
                >/dev/null 2>&1 ||
                true
        done
    fi

    OPENED_LUKS=()

    return 0
}

# ==================================================
# Reset target state
# ==================================================

reset_target_state() {
    ROOT_DEV=""
    ROOT_UUID=""
    ROOT_FSTYPE=""
    ROOT_SUBVOL=""

    ESP_DEV=""
    ESP_UUID=""
    ESP_FSTYPE=""
    ESP_MOUNT=""

    ROOTS=()

    LUKS_DEVICES=()
    OPENED_LUKS=()

    LVM_VGS=()
    LVM_LVS=()
    ACTIVATED_VGS=()

    TARGET_ROOT_MOUNTED=0
    TARGET_ESP_MOUNTED=0
}

# ==================================================
# Prepare target
# ==================================================

prepare_target() {
    require_target_commands || {
        warn "Required target detection commands are missing."
        return 1
    }

    mkdir -p "$MNT"

    # --------------------------------------------------
    # Reset state
    # --------------------------------------------------

    ROOT_DEV=""
    ROOT_UUID=""
    ROOT_FSTYPE=""
    ROOT_SUBVOL=""

    ESP_DEV=""
    ESP_UUID=""
    ESP_FSTYPE=""
    ESP_MOUNT=""

    ROOTS=()

    # Do not blindly reset OPENED_LUKS / ACTIVATED_VGS here.
    # They may contain resources belonging to this target session.

    # --------------------------------------------------
    # Storage discovery
    # --------------------------------------------------

    detect_luks_devices || true

    if ((${#LUKS_DEVICES[@]} > 0)); then
        unlock_luks || {
            warn "LUKS unlock operation failed."
            cleanup_target_storage
            return 1
        }
    fi

    # --------------------------------------------------
    # LVM activation
    # --------------------------------------------------

    if command -v vgchange >/dev/null 2>&1 &&
       command -v vgs >/dev/null 2>&1; then

        activate_lvm || {
            warn "LVM activation failed."
            cleanup_target_storage
            return 1
        }
    fi

    # --------------------------------------------------
    # Root selection
    # --------------------------------------------------

    select_root_filesystem || {
        warn "Unable to find a suitable target root filesystem."
        cleanup_target_storage
        return 1
    }

    # --------------------------------------------------
    # Btrfs subvolume
    # --------------------------------------------------

    if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
        detect_btrfs_subvolume || {
            cleanup_target_storage
            return 1
        }
    fi

    # --------------------------------------------------
    # Mount root
    # --------------------------------------------------

    mount_root || {
        warn "Failed to mount root filesystem."
        cleanup_target_storage
        return 1
    }

    # --------------------------------------------------
    # Verify Linux installation
    # --------------------------------------------------

    if [[ ! -f "$MNT/etc/os-release" ]]; then
        warn "Target does not appear to contain a Linux installation."
        cleanup_target_storage
        return 1
    fi

    # --------------------------------------------------
    # Detect and mount ESP
    # --------------------------------------------------

    detect_esp || {
        cleanup_target_storage
        return 1
    }

    detect_esp_mount

    mount_esp || {
        cleanup_target_storage
        return 1
    }

    # --------------------------------------------------
    # Final verification
    # --------------------------------------------------

    if ! is_mounted_path "$MNT"; then
        warn "Target root is not mounted."
        cleanup_target_storage
        return 1
    fi

    if ! is_mounted_path "$MNT$ESP_MOUNT"; then
        warn "Target ESP is not mounted."
        cleanup_target_storage
        return 1
    fi

    ok "Target prepared."

    return 0
}


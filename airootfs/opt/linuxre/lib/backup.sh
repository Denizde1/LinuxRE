#!/usr/bin/env bash

create_linuxre_backup() {
    local destination archive root_dir package_list
    local timestamp

    printf '%s\n' "LinuxRE Configuration Backup [MODIFIES DESTINATION ONLY]"
    printf '%s\n' "This saves configuration and package metadata; it does not repair the target."
    printf '\n'
    read -r -p "Destination directory: " destination

    if [[ -z "$destination" ]]; then
        printf '%s\n' "Destination cannot be empty." >&2
        return 1
    fi

    mkdir -p -- "$destination" || {
        printf 'Unable to create destination: %s\n' "$destination" >&2
        return 1
    }

    timestamp="$(date -u +'%Y%m%d-%H%M%SZ')"
    archive="$destination/linuxre-backup-$timestamp.tar.gz"
    root_dir="/"
    if mountpoint -q "${MNT:-/mnt}" &&
       [[ -f "${MNT:-/mnt}/etc/os-release" ]]; then
        root_dir="${MNT:-/mnt}"
    fi
    package_list="$destination/linuxre-packages-$timestamp.txt"

    if [[ -e "$archive" || -e "$package_list" ]]; then
        printf '%s\n' "A backup with the generated name already exists; refusing to overwrite." >&2
        return 1
    fi

    if [[ "$root_dir" != "/" ]] && command -v arch-chroot >/dev/null 2>&1; then
        arch-chroot "$root_dir" pacman -Qqe > "$package_list" || {
            rm -f -- "$package_list"
            printf '%s\n' "Failed to export the target package list." >&2
            return 1
        }
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Qqe > "$package_list" || {
            rm -f -- "$package_list"
            printf '%s\n' "Failed to export the package list." >&2
            return 1
        }
    else
        printf '%s\n' "pacman is unavailable; package list was not exported." > "$package_list"
    fi

    tar -czf "$archive" \
        --ignore-failed-read \
        -C "$root_dir" \
        etc/fstab etc/mkinitcpio.d etc/systemd \
        boot/loader boot/EFI boot/grub \
        2>/dev/null || {
        rm -f -- "$archive" "$package_list"
        printf '%s\n' "Backup archive creation failed." >&2
        return 1
    }

    printf 'Archive : %s\nPackages: %s\n' "$archive" "$package_list"
}

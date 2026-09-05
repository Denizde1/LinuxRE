#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/common.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/target.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/chroot.sh

# ==================================================
# Boot files
# ==================================================

get_uki_dir() {
    echo "$MNT$ESP_MOUNT/EFI/Linux"
}

get_uki_files() {
    local uki_dir

    uki_dir="$(get_uki_dir)"

    [[ -d "$uki_dir" ]] || return 0

    find "$uki_dir" \
        -maxdepth 1 \
        -type f \
        \( -iname '*.efi' -o -iname '*.EFI' \) \
        -printf '%f\n' |
        sort
}

has_uki() {
    get_uki_files | grep -q .
}

# ==================================================
# Kernel detection
# ==================================================

detect_kernel() {
    local kernel

    for kernel in \
        vmlinuz-linux \
        vmlinuz-linux-lts \
        vmlinuz-linux-zen \
        vmlinuz-linux-hardened
    do
        if [[ -f "$MNT$ESP_MOUNT/$kernel" ]]; then
            echo "$kernel"
            return 0
        fi
    done

    return 1
}

# ==================================================
# Boot type detection
# ==================================================

detect_boot_type() {

    if has_uki; then
        echo "uki"
        return 0
    fi

    if detect_kernel >/dev/null 2>&1; then
        echo "classic"
        return 0
    fi

    echo "unknown"
    return 1
}

# ==================================================
# Target verification
# ==================================================

verify_target() {

    log "Checking target..."

    if [[ ! -d "$MNT/etc" ]]; then
        warn "Target root is not mounted."
        return 1
    fi

    if [[ ! -f "$MNT/etc/os-release" ]]; then
        warn "Target does not contain /etc/os-release."
        return 1
    fi

    if grep -q '^ID=arch$' "$MNT/etc/os-release" 2>/dev/null; then
        ok "Arch Linux installation detected."
        return 0
    fi

    warn "Target does not appear to be Arch Linux."
    return 1
}

# ==================================================
# Pacman verification
# ==================================================

verify_pacman() {

    log "Checking pacman..."

    if linuxre_chroot "$MNT" pacman -V >/dev/null 2>&1; then
        ok "pacman is functional."
        return 0
    fi

    warn "pacman is not functioning."
    return 1
}

# ==================================================
# Package integrity verification
# ==================================================

verify_package_integrity() {

    log "Checking package integrity..."

    local output

    output="$(linuxre_chroot "$MNT" env LC_ALL=C pacman -Qkk 2>&1)" || {
        warn "Package integrity check failed."
        return 1
    }

    if printf '%s\n' "$output" |
        grep -qE '[1-9][0-9]* (missing|altered) files?'; then

        warn "Package integrity problems were detected."
        return 1
    fi

    ok "Package integrity check completed successfully."

    return 0
}

# ==================================================
# Package integrity repair
# ==================================================

repair_package_integrity() {
    local output
    local packages
    local package

    echo
    echo "========================================"
    echo "       Package Integrity Repair"
    echo "========================================"
    echo

    log "Checking installed packages..."

    output="$(linuxre_chroot "$MNT" env LC_ALL=C pacman -Qkk 2>&1)"

    packages="$(
        printf '%s\n' "$output" |
        awk -F: '
            /[1-9][0-9]* (missing|altered) files?/ {
                print $1
            }
        ' |
        sed 's/[[:space:]]*$//' |
        sed '/^$/d' |
        sort -u
    )"

    if [[ -z "$packages" ]]; then
        ok "No packages require repair."
        return 0
    fi

    echo

    log "Packages requiring repair:"

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue
        echo "    $package"
    done <<< "$packages"

    echo

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue

        log "Reinstalling $package..."

        if ! linuxre_chroot "$MNT" \
            pacman -S --noconfirm "$package"; then
            warn "Failed to reinstall $package."
            return 1
        fi

        ok "$package repaired."
    done <<< "$packages"

    return 0
}

# ==================================================
# Kernel verification
# ==================================================

verify_kernel() {

    local boot_type

    log "Checking kernel..."

    boot_type="$(detect_boot_type)" || {
        warn "Unable to determine boot configuration."
        return 1
    }

    case "$boot_type" in

        uki)
            ok "UKI boot configuration detected."

            if get_uki_files | grep -q .; then
                echo "    UKI files:"
                get_uki_files |
                    sed 's/^/      /'
            else
                warn "UKI configuration detected but no UKI files found."
                return 1
            fi

            ;;

        classic)
            local kernel

            if kernel="$(detect_kernel)"; then
                ok "Kernel detected: /$kernel"
            else
                warn "Kernel image was not found."
                return 1
            fi

            ;;

        *)
            warn "No supported kernel configuration detected."
            return 1
            ;;

    esac

    return 0
}

# ==================================================
# Initramfs / UKI verification
# ==================================================

verify_initramfs() {

    local boot_type

    log "Checking initramfs / UKI..."

    boot_type="$(detect_boot_type)" || {
        warn "Unable to determine boot configuration."
        return 1
    }

    case "$boot_type" in

        uki)

            if get_uki_files | grep -q .; then
                ok "UKI detected; kernel and initramfs are contained in the UKI."
                return 0
            fi

            warn "UKI configuration detected but no UKI was found."
            return 1
            ;;

        classic)

            if [[ -f "$MNT$ESP_MOUNT/initramfs-linux.img" ]]; then
                ok "Main initramfs detected."
            else
                warn "Main initramfs is missing."
                return 1
            fi

            if [[ -f "$MNT$ESP_MOUNT/initramfs-linux-fallback.img" ]]; then
                ok "Fallback initramfs detected."
            else
                warn "Fallback initramfs is missing."
            fi

            return 0
            ;;

        *)

            warn "Unknown boot configuration."
            return 1
            ;;

    esac
}

# ==================================================
# systemd verification
# ==================================================

verify_systemd() {

    log "Checking systemd..."

    if [[ -x "$MNT/usr/lib/systemd/systemd" ]]; then
        ok "systemd detected."
        return 0
    fi

    warn "systemd binary was not found."
    return 1
}

# ==================================================
# systemd-boot verification
# ==================================================

verify_systemd_boot() {

    log "Checking systemd-boot..."

    if [[ ! -x "$MNT/usr/bin/bootctl" ]]; then
        warn "bootctl was not found."
        return 1
    fi

    if [[ -f "$MNT$ESP_MOUNT/EFI/systemd/systemd-bootx64.efi" ||
          -f "$MNT$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" ]]; then

        ok "systemd-boot EFI files detected."
        return 0
    fi

    warn "systemd-boot EFI files were not found."
    return 1
}

# ==================================================
# Kernel package detection
# ==================================================

detect_kernel_package() {

    local package

    for package in \
        linux \
        linux-lts \
        linux-zen \
        linux-hardened
    do
        if linuxre_chroot "$MNT" pacman -Q "$package" >/dev/null 2>&1; then
            echo "$package"
            return 0
        fi
    done

    return 1
}

# ==================================================
# Kernel repair
# ==================================================

repair_kernel() {

    local kernel_package

    echo
    echo "========================================"
    echo "             Kernel Repair"
    echo "========================================"
    echo

    log "Detecting installed kernel package..."

    if ! kernel_package="$(detect_kernel_package)"; then
        warn "No supported kernel package is installed."
        return 1
    fi

    ok "Kernel package: $kernel_package"

    echo
    log "Reinstalling kernel package..."

    if ! linuxre_chroot "$MNT" \
        pacman -S --noconfirm "$kernel_package"; then

        warn "Kernel package installation failed."
        return 1
    fi

    ok "Kernel package repaired."

    return 0
}

# ==================================================
# Initramfs / UKI repair
# ==================================================

repair_initramfs() {

    local boot_type

    echo
    echo "========================================"
    echo "          Initramfs / UKI Repair"
    echo "========================================"
    echo

    boot_type="$(detect_boot_type)" || {
        warn "Unable to determine boot configuration."
        return 1
    }

    case "$boot_type" in

        uki)

            log "UKI configuration detected."
            log "Regenerating kernel images / UKIs..."

            ;;

        classic)

            log "Traditional kernel + initramfs configuration detected."
            log "Regenerating initramfs..."

            ;;

        *)

            warn "Unknown boot configuration."
            return 1

            ;;

    esac

    if ! linuxre_chroot "$MNT" mkinitcpio -P; then
        warn "mkinitcpio failed."
        return 1
    fi

    ok "Kernel/initramfs generation completed."

    if [[ "$boot_type" == "uki" ]]; then

        echo
        log "Checking generated UKIs..."

        if get_uki_files | grep -q .; then
            ok "UKI generation verified."

            echo "    UKI files:"
            get_uki_files |
                sed 's/^/      /'
        else
            warn "mkinitcpio completed but no UKI was found."
            return 1
        fi
    fi

    return 0
}

# ==================================================
# systemd repair
# ==================================================

repair_systemd() {

    echo
    echo "========================================"
    echo "            systemd Repair"
    echo "========================================"
    echo

    log "Reinstalling systemd..."

    if ! linuxre_chroot "$MNT" \
        pacman -S --noconfirm systemd; then

        warn "systemd reinstallation failed."
        return 1
    fi

    ok "systemd repaired."

    return 0
}

# ==================================================
# systemd-boot repair
# ==================================================

repair_systemd_boot() {

    echo
    echo "========================================"
    echo "          systemd-boot Repair"
    echo "========================================"
    echo

    log "Installing systemd-boot..."

    if ! linuxre_chroot "$MNT" bootctl install; then
        warn "systemd-boot installation failed."
        return 1
    fi

    ok "systemd-boot installed."

    return 0
}

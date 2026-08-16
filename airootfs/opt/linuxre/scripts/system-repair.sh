#!/usr/bin/env bash

set -uo pipefail

# Shared target/chroot helpers

MNT="/mnt"
TMP="$MNT/.linuxre"
LIB="/opt/linuxre/lib/chroot-common.sh"

# --------------------------------------------------
# Root check
# --------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Error: this tool must be run as root."
    exit 1
fi

# --------------------------------------------------
# Load shared helpers
# --------------------------------------------------

if [[ ! -f "$LIB" ]]; then
    echo "[ERROR] LinuxRE shared library not found:"
    echo "        $LIB"
    exit 1
fi

# shellcheck disable=SC1091
source "$LIB"

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

trap cleanup EXIT

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
    find \
    arch-chroot
do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "$cmd was not found."
        exit 1
    fi
done

# --------------------------------------------------
# Header
# --------------------------------------------------

clear

echo "╔══════════════════════════════════════════╗"
echo "║      LinuxRE System Repair (systemd)     ║"
echo "╚══════════════════════════════════════════╝"
echo

echo "Scanning installed Linux systems..."
echo

# --------------------------------------------------
# Detect root filesystems
# --------------------------------------------------

if ! detect_root_filesystems; then

    echo
    echo "No supported Linux filesystems were found."
    echo
    lsblk -f
    echo

    exit 1

fi

# --------------------------------------------------
# Display root candidates
# --------------------------------------------------

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
# Select root
# --------------------------------------------------

while true; do

    read -rp \
        "Select Linux root filesystem [1-${#ROOTS[@]}]: " \
        choice

    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#ROOTS[@]} )); then
        break
    fi

    echo "Invalid selection."

done

ROOT_DEV="${ROOTS[$((choice - 1))]}"

if ! set_root "$ROOT_DEV"; then
    echo "[ERROR] Unable to determine filesystem type."
    exit 1
fi

echo
log "Root filesystem: $ROOT_DEV"
log "Filesystem: $ROOT_FSTYPE"

# --------------------------------------------------
# Prepare target
# --------------------------------------------------

echo
log "Preparing target system..."

if ! prepare_target; then
    echo
    echo "[ERROR] Failed to prepare target system."
    exit 1
fi

ok "Target system prepared."

# --------------------------------------------------
# Detect OS
# --------------------------------------------------

PRETTY_NAME="Unknown"
ID="unknown"
VERSION_ID="unknown"

if [[ -f "$MNT/etc/os-release" ]]; then

    # shellcheck disable=SC1091
    . "$MNT/etc/os-release"

    PRETTY_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
    ID="${ID:-unknown}"
    VERSION_ID="${VERSION_ID:-unknown}"

fi

# --------------------------------------------------
# Kernel helpers
# --------------------------------------------------

find_kernel() {

    local candidate

    for candidate in \
        vmlinuz-linux \
        vmlinuz-linux-lts \
        vmlinuz-linux-zen \
        vmlinuz-linux-hardened
    do

        if [[ -f "$MNT$ESP_MOUNT/$candidate" ]]; then
            echo "$candidate"
            return 0
        fi

    done

    return 1
}

find_initramfs() {

    local candidate="$1"

    if [[ -f "$MNT$ESP_MOUNT/$candidate" ]]; then
        return 0
    fi

    return 1
}

# --------------------------------------------------
# UKI helpers
# --------------------------------------------------

find_uki() {
    local uki_dir="$MNT$ESP_MOUNT/EFI/Linux"

    [[ -d "$uki_dir" ]] || return 1

    find "$uki_dir"         -maxdepth 1         -type f         -iname '*.efi'         -printf '%f\n' |
        sort
}

has_uki() {
    local uki
    uki="$(find_uki | head -n1)"
    [[ -n "$uki" ]]
}

# --------------------------------------------------
# Diagnosis
# --------------------------------------------------

diagnose_system() {

    local kernel=""
    local systemd_ok=0
    local bootloader_ok=0
    local uki_found=0

    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║              System Diagnosis            ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    echo "Operating system:"
    echo "  Name       : $PRETTY_NAME"
    echo "  ID         : $ID"
    echo "  Version    : $VERSION_ID"

    echo
    echo "Root filesystem:"
    echo "  Device     : $ROOT_DEV"
    echo "  Filesystem : $ROOT_FSTYPE"

    if [[ -n "$ROOT_SUBVOL" ]]; then
        echo "  Subvolume  : $ROOT_SUBVOL"
    fi

    echo
    echo "EFI System Partition:"
    echo "  Device     : $ESP_DEV"
    echo "  Filesystem : ${ESP_FSTYPE:-Unknown}"
    echo "  Mount      : $ESP_MOUNT"

    echo
    echo "Boot images:"
    echo

    if kernel="$(find_kernel)"; then
        echo "[OK] Kernel detected: /$kernel"
    else
        echo "[FAIL] Linux kernel image not found."
    fi

    if find_initramfs "initramfs-linux.img"; then
        echo "[OK] Main initramfs detected."
    else
        echo "[FAIL] Main initramfs not found."
    fi

    if find_initramfs "initramfs-linux-fallback.img"; then
        echo "[OK] Fallback initramfs detected."
    else
        echo "[WARN] Fallback initramfs not found."
    fi

    echo
    echo "Unified Kernel Images:"
    echo

    mapfile -t diagnosis_uki_files < <(find_uki)

    if (( ${#diagnosis_uki_files[@]} > 0 )); then
        uki_found=1
        for uki in "${diagnosis_uki_files[@]}"; do
            echo "[OK] UKI detected: /EFI/Linux/$uki"
        done
    else
        echo "[INFO] No Unified Kernel Image detected."
    fi

    echo
    echo "systemd:"
    echo

    if [[ -x "$MNT/usr/lib/systemd/systemd" ||
          -x "$MNT/usr/bin/systemd" ]]; then

        systemd_ok=1
        echo "[OK] systemd installation detected."

    else

        echo "[FAIL] systemd installation not detected."

    fi

    echo
    echo "systemd-boot:"
    echo

    if [[ -f "$MNT$ESP_MOUNT/EFI/systemd/systemd-bootx64.efi" ||
          -f "$MNT$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" ]]; then

        bootloader_ok=1
        echo "[OK] systemd-boot files detected."

    else

        echo "[WARN] systemd-boot files were not detected."

    fi

    echo
    echo "────────────────────────────────────────────"
    echo

    if (( systemd_ok && bootloader_ok )); then
        echo "[OK] systemd boot environment appears intact."
    else
        echo "[WARN] One or more system components require repair."
    fi

    echo

}

# --------------------------------------------------
# Kernel & initramfs repair
# --------------------------------------------------

repair_kernel_initramfs() {
    local _repair_cleanup_done=0
    trap 'if (( _repair_cleanup_done == 0 )); then cleanup; fi' RETURN

    # Prepare the target system using shared LinuxRE helpers.
    if ! prepare_target; then
        warn "Failed to prepare target system."
        return 1
    fi

    if ! prepare_chroot; then
        warn "Failed to prepare chroot environment."
        cleanup
        return 1
    fi

    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║       Kernel & Initramfs Repair          ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    local kernel_package=""
    local kernel=""

    # --------------------------------------------------
    # Detect installed kernel package
    # --------------------------------------------------

    echo "[+] Checking installed kernel packages..."

    for package in \
        linux \
        linux-lts \
        linux-zen \
        linux-hardened
    do

        if arch-chroot "$MNT" pacman -Q "$package" >/dev/null 2>&1; then
            kernel_package="$package"
            break
        fi

    done

    if [[ -n "$kernel_package" ]]; then
        echo "[OK] Installed kernel package: $kernel_package"
    else
        echo "[WARN] No supported kernel package detected."
    fi

    # --------------------------------------------------
    # Check kernel
    # --------------------------------------------------

    echo
    echo "[+] Checking kernel image..."

    if kernel="$(find_kernel)"; then

        echo "[OK] Kernel found: /$kernel"

    else

        echo "[FAIL] Kernel image is missing."

        if [[ -z "$kernel_package" ]]; then
            echo "[ERROR] No kernel package is available for automatic repair."
            return 1
        fi

        echo
        echo "Installed package:"
        echo "  $kernel_package"
        echo
        echo "The package will be reinstalled."
        echo

        read -rp "Continue? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 1
        fi

        echo
        echo "[+] Reinstalling $kernel_package..."

        if ! arch-chroot "$MNT" pacman -S --noconfirm "$kernel_package"; then
            echo "[FAIL] Kernel package installation failed."
            return 1
        fi

        echo "[OK] Kernel package reinstalled."

    fi

    # --------------------------------------------------
    # Rebuild initramfs
    # --------------------------------------------------

    echo
    echo "[+] Regenerating initramfs..."

    if ! arch-chroot "$MNT" mkinitcpio -P; then
        echo
        echo "[FAIL] mkinitcpio failed."
        return 1
    fi

    echo "[OK] initramfs regeneration completed."

    # --------------------------------------------------
    # Final verification
    # --------------------------------------------------

    echo
    echo "[+] Verifying boot files..."

    if ! kernel="$(find_kernel)"; then
        echo "[FAIL] Kernel is still missing."
        return 1
    fi

    if ! find_initramfs "initramfs-linux.img"; then
        echo "[FAIL] Main initramfs is still missing."
        return 1
    fi

    echo "[OK] Kernel: /$kernel"
    echo "[OK] Initramfs: /initramfs-linux.img"

    echo
    echo "Kernel and initramfs repair completed."

    trap - RETURN
    cleanup

}

# --------------------------------------------------
# systemd repair
# --------------------------------------------------

repair_systemd() {
    local _repair_cleanup_done=0
    trap 'if (( _repair_cleanup_done == 0 )); then cleanup; fi' RETURN

    # Prepare the target system using shared LinuxRE helpers.
    if ! prepare_target; then
        warn "Failed to prepare target system."
        return 1
    fi

    if ! prepare_chroot; then
        warn "Failed to prepare chroot environment."
        cleanup
        return 1
    fi


    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║            systemd Repair                ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    echo "[+] Checking systemd installation..."
    echo

    local systemd_bin=""
    local systemd_package=""

    # --------------------------------------------------
    # Locate systemd
    # --------------------------------------------------

    if [[ -x "$MNT/usr/lib/systemd/systemd" ]]; then
        systemd_bin="/usr/lib/systemd/systemd"
    elif [[ -x "$MNT/usr/bin/systemd" ]]; then
        systemd_bin="/usr/bin/systemd"
    fi

    if [[ -n "$systemd_bin" ]]; then
        echo "[OK] systemd binary found: $systemd_bin"
    else
        echo "[FAIL] systemd binary was not found."
    fi

    # --------------------------------------------------
    # Check package
    # --------------------------------------------------

    if arch-chroot "$MNT" pacman -Q systemd >/dev/null 2>&1; then

        systemd_package="$(
            arch-chroot "$MNT" pacman -Q systemd
        )"

        echo "[OK] systemd package installed:"
        echo "     $systemd_package"

    else

        echo "[FAIL] systemd package is not installed."

    fi

    # --------------------------------------------------
    # Check systemd files
    # --------------------------------------------------

    echo
    echo "[+] Checking essential systemd files..."

    local failed=0

    for file in \
        /usr/lib/systemd/systemd \
        /usr/bin/systemctl \
        /usr/bin/journalctl \
        /usr/bin/loginctl \
        /usr/bin/bootctl
    do

        if [[ -e "$MNT$file" ]]; then
            echo "[OK] $file"
        else
            echo "[FAIL] $file"
            failed=1
        fi

    done

    # --------------------------------------------------
    # Verify package files
    # --------------------------------------------------

    echo
    echo "[+] Verifying systemd package files..."

    if arch-chroot "$MNT" pacman -Qk systemd >/dev/null 2>&1; then

        echo "[OK] systemd package verification passed."

    else

        echo "[WARN] systemd package verification reported missing files."
        failed=1

    fi

    # --------------------------------------------------
    # Repair confirmation
    # --------------------------------------------------

    echo

    if (( failed == 0 )); then

        echo "[OK] No obvious systemd installation problems were detected."
        echo
        read -rp "Reinstall systemd anyway? [y/N]: " confirm

    else

        echo "[!] systemd installation appears damaged."
        echo
        read -rp "Reinstall systemd now? [Y/n]: " confirm
        confirm="${confirm:-Y}"

    fi

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo
        echo "Cancelled."
        cleanup
        return 0
    fi

    # --------------------------------------------------
    # Reinstall systemd
    # --------------------------------------------------

    echo
    echo "[+] Reinstalling systemd..."
    echo

    if ! arch-chroot "$MNT" pacman -S --noconfirm systemd; then

        echo
        echo "[FAIL] systemd reinstallation failed."
        echo
        echo "Check network connectivity and pacman configuration."
        echo

        return 1

    fi

    echo
    echo "[OK] systemd package reinstalled."

    # --------------------------------------------------
    # Verify again
    # --------------------------------------------------

    echo
    echo "[+] Verifying repaired systemd installation..."

    if [[ ! -x "$MNT/usr/lib/systemd/systemd" ]]; then

        echo "[FAIL] systemd binary is still missing."
        return 1

    fi

    if ! arch-chroot "$MNT" pacman -Qk systemd >/dev/null 2>&1; then

        echo "[WARN] systemd package verification still reports problems."

    else

        echo "[OK] systemd package verification passed."

    fi

    echo
    echo "╔══════════════════════════════════════════╗"
    echo "║       systemd repair completed           ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    trap - RETURN
    cleanup

    return 0
}

# --------------------------------------------------
# systemd-boot repair
# --------------------------------------------------

repair_systemd_boot() {
    local _repair_cleanup_done=0
    trap 'if (( _repair_cleanup_done == 0 )); then cleanup; fi' RETURN

    # Prepare the target system using shared LinuxRE helpers.
    if ! prepare_target; then
        warn "Failed to prepare target system."
        return 1
    fi

    if ! prepare_chroot; then
        warn "Failed to prepare chroot environment."
        cleanup
        return 1
    fi


    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║          systemd-boot Repair             ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    echo "Target:"
    echo "  Root : $ROOT_DEV"
    echo "  ESP  : $ESP_DEV"
    echo "  Mount: $ESP_MOUNT"
    echo

    # --------------------------------------------------
    # Verify EFI environment
    # --------------------------------------------------

    if [[ ! -d "$MNT$ESP_MOUNT" ]]; then
        echo "[FAIL] EFI System Partition mount point does not exist."
        return 1
    fi

    if ! mountpoint -q "$MNT$ESP_MOUNT"; then
        echo "[FAIL] EFI System Partition is not mounted."
        return 1
    fi

    echo "[OK] EFI System Partition is mounted."

    # --------------------------------------------------
    # Check bootctl
    # --------------------------------------------------

    if [[ ! -x "$MNT/usr/bin/bootctl" ]]; then
        echo
        echo "[FAIL] bootctl was not found."
        echo "       The systemd package may be damaged."
        return 1
    fi

    echo "[OK] bootctl found."

    # --------------------------------------------------
    # Detect existing systemd-boot
    # --------------------------------------------------

    echo
    echo "[+] Checking existing systemd-boot installation..."
    echo

    if arch-chroot "$MNT" bootctl is-installed >/dev/null 2>&1; then
        echo "[OK] systemd-boot is currently installed."
    else
        echo "[WARN] systemd-boot is not currently installed."
    fi

    # --------------------------------------------------
    # Confirmation
    # --------------------------------------------------

    echo
    echo "The following actions will be performed:"
    echo
    echo "  1. Install/reinstall systemd-boot"
    echo "  2. Recreate loader.conf"
    echo "  3. Detect kernel/initramfs or UKI"
    echo "  4. Recreate the Arch Linux loader entry"
    echo "  5. Verify the installation"
    echo
    echo "Windows Boot Manager and other EFI bootloaders"
    echo "will not be intentionally removed."
    echo

    read -rp "Continue? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo
        echo "Cancelled."
        return 0
    fi

    # --------------------------------------------------
    # Install systemd-boot
    # --------------------------------------------------

    echo
    echo "[+] Installing systemd-boot..."

    if ! arch-chroot "$MNT" bootctl install; then

        echo
        echo "[FAIL] systemd-boot installation failed."
        return 1

    fi

    echo "[OK] systemd-boot installed."

    # --------------------------------------------------
    # Create loader directory
    # --------------------------------------------------

    mkdir -p \
        "$MNT$ESP_MOUNT/loader/entries"

    # --------------------------------------------------
    # loader.conf
    # --------------------------------------------------

    echo
    echo "[+] Creating loader.conf..."

    cat > "$MNT$ESP_MOUNT/loader/loader.conf" <<EOF
default arch.conf
timeout 3
editor no
EOF

    if [[ $? -ne 0 ]]; then
        echo "[FAIL] Failed to create loader.conf."
        return 1
    fi

    echo "[OK] loader.conf created."

    # --------------------------------------------------
    # Detect kernel
    # --------------------------------------------------

    local kernel=""
    local initramfs=""
    local uki=""
    local boot_type=""

    echo
    echo "[+] Detecting boot images..."

    if kernel="$(find_kernel)"; then

        initramfs="initramfs-linux.img"

        if [[ -f "$MNT$ESP_MOUNT/$initramfs" ]]; then
            boot_type="kernel"
        fi

    fi

    # --------------------------------------------------
    # Detect UKI
    # --------------------------------------------------

    if [[ -z "$boot_type" &&
          -d "$MNT$ESP_MOUNT/EFI/Linux" ]]; then

        mapfile -t uki_files < <(
            find "$MNT$ESP_MOUNT/EFI/Linux" \
                -maxdepth 1 \
                -type f \
                -iname '*.efi' \
                -printf '%f\n' |
            sort
        )

        if (( ${#uki_files[@]} == 1 )); then

            uki="${uki_files[0]}"
            boot_type="uki"

        elif (( ${#uki_files[@]} > 1 )); then

            echo
            echo "Multiple Unified Kernel Images found:"
            echo

            for i in "${!uki_files[@]}"; do
                printf "  %d) %s\n" \
                    "$((i + 1))" \
                    "${uki_files[$i]}"
            done

            echo

            read -rp \
                "Select UKI [1-${#uki_files[@]}]: " \
                uki_choice

            if [[ "$uki_choice" =~ ^[0-9]+$ ]] &&
               (( uki_choice >= 1 &&
                  uki_choice <= ${#uki_files[@]} )); then

                uki="${uki_files[$((uki_choice - 1))]}"
                boot_type="uki"

            else

                echo "[FAIL] Invalid UKI selection."
                        return 1

            fi

        fi

    fi

    # --------------------------------------------------
    # Rebuild initramfs if required
    # --------------------------------------------------

    if [[ -z "$boot_type" ]]; then

        echo
        echo "[WARN] No usable kernel/initramfs or UKI detected."
        echo

        if [[ -z "$kernel" ]]; then

            echo "[FAIL] No Linux kernel image was found."
            echo
            echo "Use 'Repair kernel and initramfs' first."
                return 1

        fi

        echo "[+] Kernel found: /$kernel"
        echo "[+] Rebuilding initramfs..."

        if ! arch-chroot "$MNT" mkinitcpio -P; then

            echo
            echo "[FAIL] mkinitcpio failed."
                return 1

        fi

        echo "[OK] initramfs regeneration completed."

        if [[ -f "$MNT$ESP_MOUNT/initramfs-linux.img" ]]; then
            initramfs="initramfs-linux.img"
            boot_type="kernel"
        fi

    fi

    # --------------------------------------------------
    # Validate boot type
    # --------------------------------------------------

    case "$boot_type" in

        kernel)

            echo
            echo "[OK] Boot mode: kernel + initramfs"
            echo "     Kernel    : /$kernel"
            echo "     Initramfs : /$initramfs"

            ;;

        uki)

            echo
            echo "[OK] Boot mode: Unified Kernel Image"
            echo "     UKI: /EFI/Linux/$uki"

            ;;

        *)

            echo
            echo "[FAIL] No usable boot image was found."
                return 1

            ;;

    esac

    # --------------------------------------------------
    # Create Arch loader entry
    # --------------------------------------------------

    echo
    echo "[+] Creating Arch Linux loader entry..."

    if [[ "$boot_type" == "uki" ]]; then

        cat > \
            "$MNT$ESP_MOUNT/loader/entries/arch.conf" <<EOF
title   Arch Linux
efi     /EFI/Linux/$uki
EOF

    else

        cat > \
            "$MNT$ESP_MOUNT/loader/entries/arch.conf" <<EOF
title   Arch Linux
linux   /$kernel
initrd  /$initramfs
options root=UUID=$ROOT_UUID rw
EOF

    fi

    if [[ $? -ne 0 ]]; then
        echo "[FAIL] Failed to create arch.conf."
        return 1
    fi

    echo "[OK] arch.conf created."

    # --------------------------------------------------
    # Verify files
    # --------------------------------------------------

    echo
    echo "[+] Verifying systemd-boot installation..."

    if ! arch-chroot "$MNT" bootctl status; then
        echo
        echo "[WARN] bootctl status reported an issue."
    fi

    echo
    echo "[+] Verifying loader files..."

    if [[ ! -f "$MNT$ESP_MOUNT/loader/loader.conf" ]]; then
        echo "[FAIL] loader.conf verification failed."
        return 1
    fi

    if [[ ! -f "$MNT$ESP_MOUNT/loader/entries/arch.conf" ]]; then
        echo "[FAIL] arch.conf verification failed."
        return 1
    fi

    echo "[OK] loader.conf verified."
    echo "[OK] arch.conf verified."

    if [[ "$boot_type" == "kernel" ]]; then

        [[ -f "$MNT$ESP_MOUNT/$kernel" ]] ||
            return 1

        [[ -f "$MNT$ESP_MOUNT/$initramfs" ]] ||
            return 1

        echo "[OK] Kernel verified."
        echo "[OK] Initramfs verified."

    else

        [[ -f "$MNT$ESP_MOUNT/EFI/Linux/$uki" ]] ||
            return 1

        echo "[OK] UKI verified."

    fi

    echo
    echo "╔══════════════════════════════════════════╗"
    echo "║     systemd-boot repair completed        ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    trap - RETURN
    cleanup

    return 0
}

# --------------------------------------------------
# Tool runner
# --------------------------------------------------

run_tool() {
    "$@"
    local status=$?

    echo
    echo "Returning to Recovery menu in 5 seconds..."
    sleep 5

    return "$status"
}

# --------------------------------------------------
# Main menu
# --------------------------------------------------

while true; do

    clear

    echo "╔══════════════════════════════════════════╗"
    echo "║      LinuxRE System Repair (systemd)     ║"
    echo "╚══════════════════════════════════════════╝"
    echo

    echo "Target:"
    echo "  OS       : $PRETTY_NAME"
    echo "  Root     : $ROOT_DEV"
    echo "  Filesystem: $ROOT_FSTYPE"

    [[ -n "$ROOT_SUBVOL" ]] &&
        echo "  Subvolume: $ROOT_SUBVOL"

    echo "  ESP      : $ESP_DEV"
    echo "  ESP mount: $ESP_MOUNT"

    echo
    echo "────────────────────────────────────────────"
    echo
    echo "  1) System diagnosis"
    echo "  2) Repair kernel and initramfs"
    echo "  3) Repair systemd"
    echo "  4) Repair systemd-boot"
    echo "  5) Exit"
    echo
    echo "────────────────────────────────────────────"
    echo

    read -rp "Select an option [1-5]: " option

    case "$option" in

        1)
            run_tool diagnose_system
            ;;

        2)
            run_tool repair_kernel_initramfs
            ;;

        3)
            run_tool repair_systemd
            ;;

        4)
            run_tool repair_systemd_boot
            ;;

        5)
            echo
            echo "Exiting System Repair..."
            exit 0
            ;;

        *)
            echo
            echo "Invalid option."
            sleep 2
            ;;

    esac

done

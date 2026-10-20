#!/usr/bin/env bash
# shellcheck disable=SC2329

set -uo pipefail
# Test doubles are invoked indirectly by the library functions under test.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0

pass_test() {
    printf '[PASS] %s\n' "$1"
    pass=$((pass + 1))
}

fail_test() {
    printf '[FAIL] %s\n' "$1" >&2
    fail=$((fail + 1))
}

assert_true() {
    local name="$1"
    shift

    if "$@"; then
        pass_test "$name"
    else
        fail_test "$name"
    fi
}

assert_file_contains() {
    local name="$1"
    local pattern="$2"
    local file="$3"

    if grep -qE "$pattern" "$file"; then
        pass_test "$name"
    else
        fail_test "$name"
    fi
}

LIB_DIR="$TMP_DIR/opt/linuxre/lib"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$LIB_DIR" "$BIN_DIR"
cp "$ROOT_DIR"/airootfs/opt/linuxre/lib/{common,target,repair,chroot,imaging,diagnostics,fsck}.sh "$LIB_DIR/"

cat > "$BIN_DIR/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$BIN_DIR/umount" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$BIN_DIR/vgchange" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$BIN_DIR/cryptsetup" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$BIN_DIR/blkid" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-s TYPE"* ]]; then
    echo ext4
    exit 0
fi
if [[ "$*" == *"-s UUID"* ]]; then
    echo 11111111-2222-3333-4444-555555666666
    exit 0
fi
exit 0
EOF
cat > "$BIN_DIR/lvs" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--select"* ]]; then
    echo vg
    exit 0
fi
exit 0
EOF
chmod +x "$BIN_DIR"/*

export PATH="$BIN_DIR:$PATH"
export MNT="$TMP_DIR/mnt"
export TMP="$TMP_DIR/state"
export REPORT_LOG_PATH="$TMP_DIR/report.log"
export REPORT_FILE_PATH="$TMP_DIR/report.txt"
mkdir -p "$MNT" "$TMP"
: > "$TMP/sentinel"

# The copied libraries use absolute source paths only in repair/chroot.
# Rewrite those paths in the temporary test copy; repository files remain untouched.
sed -i "s#/opt/linuxre/lib#$LIB_DIR#g" \
    "$LIB_DIR"/target.sh "$LIB_DIR"/repair.sh "$LIB_DIR"/chroot.sh "$LIB_DIR"/diagnostics.sh

# shellcheck disable=SC1091
source "$LIB_DIR/common.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/target.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/chroot.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/repair.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/imaging.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/diagnostics.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/fsck.sh"

trap 'cleanup; rm -rf -- "$TMP_DIR"' EXIT

mkdir -p "$MNT/etc"
printf '%s\n' 'UUID=deadbeef /boot/efi vfat defaults 0 2' > "$MNT/etc/fstab"
ESP_MOUNT=""
detect_esp_mount
assert_true "ESP detection respects /boot/efi mountpoints" test "$ESP_MOUNT" = "/boot/efi"

ROOT_DEV="/dev/mapper/vg-lv"
TARGET_LVM_VG=""
base_name="${ROOT_DEV#/dev/}"
if [[ "$ROOT_DEV" =~ ^/dev/([^/]+)/([^/]+)$ ]] && [[ "$ROOT_DEV" != /dev/mapper/* ]]; then
    if [[ "$base_name" == */* ]]; then
        TARGET_LVM_VG="${base_name%%/*}"
    fi
fi
assert_true "mapper aliases do not masquerade as LVM volume groups" test -z "$TARGET_LVM_VG"

TARGET_INSPECTION_MOUNTS=("$TMP_DIR/inspection")
if cleanup_target_storage; then
    fail_test "failed inspection unmount propagates failure"
else
    pass_test "failed inspection unmount propagates failure"
fi

if ((${#TARGET_INSPECTION_MOUNTS[@]} == 1)) &&
   [[ "${TARGET_INSPECTION_MOUNTS[0]}" == "$TMP_DIR/inspection" ]]; then
    pass_test "failed inspection unmount preserves ownership state"
else
    fail_test "failed inspection unmount preserves ownership state"
fi

if (
    ROOT_DEV=/dev/test-root
    ROOT_FSTYPE=ext4
    ROOT_SUBVOL=""
    MNT="$TMP_DIR/pre-mounted-root"
    TEST_MOUNT_SOURCE=/dev/test-root
    findmnt() {
        case "$*" in
            *SOURCE*) printf '%s\n' "$TEST_MOUNT_SOURCE" ;;
            *FSTYPE*) printf '%s\n' ext4 ;;
        esac
    }
    readlink() {
        case "${@: -1}" in
            /dev/test-root) printf '%s\n' /dev/test-root ;;
            /dev/other-root) printf '%s\n' /dev/other-root ;;
            *) return 1 ;;
        esac
    }
    mount_root
); then
    pass_test "selected filesystem is accepted when already mounted"
else
    fail_test "selected filesystem is accepted when already mounted"
fi

if (
    ROOT_DEV=/dev/test-root
    ROOT_FSTYPE=ext4
    ROOT_SUBVOL=""
    MNT="$TMP_DIR/pre-mounted-root"
    TEST_MOUNT_SOURCE=/dev/other-root
    findmnt() {
        case "$*" in
            *SOURCE*) printf '%s\n' "$TEST_MOUNT_SOURCE" ;;
            *FSTYPE*) printf '%s\n' ext4 ;;
        esac
    }
    readlink() {
        case "${@: -1}" in
            /dev/test-root) printf '%s\n' /dev/test-root ;;
            /dev/other-root) printf '%s\n' /dev/other-root ;;
            *) return 1 ;;
        esac
    }
    mount_root
); then
    fail_test "different pre-mounted filesystem is rejected"
else
    pass_test "different pre-mounted filesystem is rejected"
fi

if (
    ROOT_DEV=/dev/test-root
    # shellcheck disable=SC2034
    ROOT_FSTYPE=btrfs
    # shellcheck disable=SC2034
    ROOT_SUBVOL=@
    MNT="$TMP_DIR/pre-mounted-root"
    TEST_MOUNT_FSROOT=/
    findmnt() {
        case "$*" in
            *SOURCE*) printf '%s\n' /dev/test-root ;;
            *FSTYPE*) printf '%s\n' btrfs ;;
            *FSROOT*) printf '%s\n' "$TEST_MOUNT_FSROOT" ;;
        esac
    }
    readlink() {
        printf '%s\n' /dev/test-root
    }
    mount_root
); then
    fail_test "different pre-mounted Btrfs subvolume is rejected"
else
    pass_test "different pre-mounted Btrfs subvolume is rejected"
fi

if (
    MNT="$TMP_DIR/chroot"
    mountpoint() { return 1; }
    mount() {
        [[ "$1" == "--rbind" ]] && return 0
        return 1
    }
    umount() { return 1; }
    CHROOT_RUNTIME_MOUNTS=()
    if bind_chroot_runtime_mount /dev "$TMP_DIR/chroot/dev"; then
        exit 1
    fi
    ((${#CHROOT_RUNTIME_MOUNTS[@]} == 1)) &&
        [[ "${CHROOT_RUNTIME_MOUNTS[0]}" == "$TMP_DIR/chroot/dev" ]]
); then
    pass_test "failed chroot remount setup keeps bind mount tracked"
else
    fail_test "failed chroot remount setup keeps bind mount tracked"
fi

mkdir -p "$TMP_DIR/symlink-root" "$TMP_DIR/outside"
ln -s "$TMP_DIR/outside" "$TMP_DIR/symlink-root/dev"
if target_path_is_within_root "$TMP_DIR/symlink-root" "$TMP_DIR/symlink-root/dev"; then
    fail_test "chroot mount paths cannot escape through symlinks"
else
    pass_test "chroot mount paths cannot escape through symlinks"
fi
if (
    MNT="$TMP_DIR/symlink-root"
    ESP_MOUNT=/dev
    ESP_DEV=/dev/test-esp
    mount_esp
); then
    fail_test "ESP mount refuses symlink path outside target root"
else
    pass_test "ESP mount refuses symlink path outside target root"
fi
if (
    MNT="$TMP_DIR/esp-root"
    ESP_MOUNT=/boot
    # shellcheck disable=SC2034
    ESP_DEV=/dev/test-esp
    TARGET_ESP_MOUNTED=0
    mkdir -p "$MNT"
    mountpoint() { return 1; }
    findmnt() { return 1; }
    mount() { return 0; }
    umount() { return 1; }
    if mount_esp; then
        exit 1
    fi
    (( TARGET_ESP_MOUNTED == 1 ))
); then
    pass_test "failed ESP mount verification preserves cleanup ownership"
else
    fail_test "failed ESP mount verification preserves cleanup ownership"
fi

assert_file_contains "Btrfs library check is read-only" 'btrfs check --readonly' \
    "$ROOT_DIR/airootfs/opt/linuxre/lib/fsck.sh"
# Literal grep pattern checks the script's "$1" and "$2" parameters.
# shellcheck disable=SC2016
assert_file_contains "interactive filesystem checks use the read-only helper" \
    'check_filesystem "\$1" "\$2"' \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/fsck.sh"
if grep -Eq 'fsck\.fat -a|ntfsfix' "$ROOT_DIR/airootfs/opt/linuxre/tools/fsck.sh"; then
    fail_test "interactive filesystem check does not auto-repair FAT or NTFS"
else
    pass_test "interactive filesystem check does not auto-repair FAT or NTFS"
fi
if grep -R -- '--repair' "$ROOT_DIR/airootfs/opt/linuxre/lib/fsck.sh" \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/fsck.sh" >/dev/null; then
    fail_test "Btrfs repair remains disabled"
else
    pass_test "Btrfs repair remains disabled"
fi
assert_file_contains "DNS override stays opt-in" 'LINUXRE_DNS' \
    "$ROOT_DIR/airootfs/usr/local/bin/linuxre-dns"
if grep -qw 'memdisk' \
    "$ROOT_DIR/airootfs/etc/mkinitcpio.conf.d/archiso.conf"; then
    fail_test "UEFI initramfs does not request the unavailable memdiskfind helper"
else
    pass_test "UEFI initramfs does not request the unavailable memdiskfind helper"
fi
if grep -q '8\.8\.8\.8' "$ROOT_DIR/airootfs/usr/local/bin/linuxre-dns"; then
    fail_test "DNS override no longer hard-codes Google DNS"
else
    pass_test "DNS override no longer hard-codes Google DNS"
fi
assert_file_contains "DNS service waits for network readiness" 'network-online.target' \
    "$ROOT_DIR/airootfs/etc/systemd/system/linuxre-dns.service"

mkdir -p "$TMP_DIR/boot-target/boot"
MNT="$TMP_DIR/boot-target"
ESP_MOUNT="/efi"
: > "$MNT/boot/vmlinuz-linux"
if [[ "$(detect_kernel)" == "vmlinuz-linux" ]]; then
    pass_test "classic kernel detection checks /boot when ESP is separate"
else
    fail_test "classic kernel detection checks /boot when ESP is separate"
fi

assert_true "e2fsck status 1 means errors were corrected" \
    e2fsck_status_is_acceptable 1
assert_true "e2fsck status 2 is an accepted reboot-required result" \
    e2fsck_status_is_acceptable 2
if e2fsck_status_is_acceptable 4; then
    fail_test "e2fsck status 4 remains a repair failure"
else
    pass_test "e2fsck status 4 remains a repair failure"
fi

safe_image="$TMP_DIR/safe.img"
printf 'image' > "$safe_image"
assert_true "regular image destinations are accepted" imaging_output_path_is_safe "$safe_image"
ln "$safe_image" "$TMP_DIR/hardlink.img"
if imaging_output_path_is_safe "$TMP_DIR/hardlink.img" >/dev/null 2>&1; then
    fail_test "multiply-linked image destinations are rejected"
else
    pass_test "multiply-linked image destinations are rejected"
fi
ln -s "$safe_image" "$TMP_DIR/image-link"
if imaging_output_path_is_safe "$TMP_DIR/image-link" >/dev/null 2>&1; then
    fail_test "image destination symlinks are rejected"
else
    pass_test "image destination symlinks are rejected"
fi
assert_true "image mapfiles remain beside the image for resume" \
    test "$(imaging_map_path create /dev/test "$safe_image")" = "$safe_image.map"
assert_true "restore mapfiles remain beside the image for resume" \
    test "$(imaging_map_path restore "$safe_image" /dev/test)" = "$safe_image.restore.map"
assert_true "clone mapfiles use the requested persistent path" \
    test "$(imaging_map_path clone /dev/source /dev/target "$TMP_DIR/clone.map")" = "$TMP_DIR/clone.map"
ln -s "$safe_image" "$TMP_DIR/unsafe.img.map"
if imaging_map_path create /dev/test "$TMP_DIR/unsafe.img" >/dev/null 2>&1; then
    fail_test "mapfile symlinks are rejected"
else
    pass_test "mapfile symlinks are rejected"
fi

lsblk() {
    case "$*" in
        *"--inverse"*"/dev/test-disk"*)
            printf '%s\n' /dev/test-disk
            ;;
        *"--inverse"*"/dev/test-part"*)
            printf '%s\n' /dev/test-part /dev/test-disk
            ;;
        *"--inverse"*"/dev/another-disk"*)
            printf '%s\n' /dev/another-disk
            ;;
        *"/dev/test-disk"*)
            printf '%s\n' /dev/test-disk /dev/test-part
            ;;
        *"/dev/test-part"*)
            printf '%s\n' /dev/test-part
            ;;
        *"/dev/another-disk"*)
            printf '%s\n' /dev/another-disk
            ;;
        *)
            return 1
            ;;
    esac
}
findmnt() {
    [[ "$*" == *"/dev/test-part"* ]] && return 0
    return 1
}
assert_true "whole-disk mount detection includes mounted child partitions" \
    imaging_device_is_mounted /dev/test-disk
assert_true "source and target parent/child pairs are rejected" \
    imaging_devices_overlap /dev/test-disk /dev/test-part
if imaging_devices_overlap /dev/test-disk /dev/another-disk; then
    fail_test "unrelated disks are not reported as overlapping"
else
    pass_test "unrelated disks are not reported as overlapping"
fi

mkdir -p "$MNT/var/cache/pacman/pkg"
: > "$MNT/var/cache/pacman/pkg/cached.pkg.tar.zst"
diagnostics_output="$(package_diagnostics)"
if [[ "$diagnostics_output" == *"Cached packages: 1"* &&
      "$diagnostics_output" == *"cached.pkg.tar.zst"* ]]; then
    pass_test "package diagnostics list cached packages"
else
    fail_test "package diagnostics list cached packages"
fi
report_result="$(
    system_information() { :; }
    storage_explorer() { :; }
    luks_diagnostics() { :; }
    btrfs_snapshots() { :; }
    boot_browser() { :; }
    fstab_diagnostics() { :; }
    package_diagnostics() { :; }
    network_diagnostics() { :; }
    user_diagnostics() { :; }
    journal_diagnostics() { :; }
    chmod() { return 1; }
    if write_report "$TMP_DIR/permission-report.txt" >/dev/null 2>&1; then
        printf 'success\n'
    else
        printf 'failure-propagated\n'
    fi
)"
if [[ "$report_result" == "failure-propagated" ]]; then
    pass_test "recovery report permission failures propagate"
else
    fail_test "recovery report permission failures propagate"
fi

assert_file_contains "system diagnostics menu sources the diagnostic library" \
    'source /opt/linuxre/lib/diagnostics.sh; trap cleanup EXIT' \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/system.sh"
assert_file_contains "recovery report menu runs with required privileges" \
    'sudo bash -c .*write_report' \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/recovery.sh"
assert_file_contains "disk clone asks for a persistent resume map" \
    'Map file path on persistent storage' \
    "$ROOT_DIR/airootfs/opt/linuxre/lib/clone-disk.sh"
assert_true "NetworkManager remains enabled for the live network workflow" \
    test -L "$ROOT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
assert_true "systemd-networkd is not enabled alongside NetworkManager" \
    test ! -L "$ROOT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
assert_true "systemd-networkd wait-online cannot block network-online" \
    test ! -L "$ROOT_DIR/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
assert_true "standalone iwd is not enabled beside NetworkManager" \
    test ! -L "$ROOT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service"
if grep -qx 'iwd' "$ROOT_DIR/packages.x86_64"; then
    fail_test "unconfigured iwd backend is not included"
else
    pass_test "unconfigured iwd backend is not included"
fi
assert_true "masked systemd-resolved is not enabled" \
    test ! -L "$ROOT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
assert_true "unshipped VM guest services are not enabled" \
    test ! -L "$ROOT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/vmtoolsd.service"
assert_file_contains "SSH password authentication is disabled" \
    '^PasswordAuthentication no$' \
    "$ROOT_DIR/airootfs/etc/ssh/sshd_config.d/10-archiso.conf"
assert_file_contains "SSH root login is disabled" \
    '^PermitRootLogin no$' \
    "$ROOT_DIR/airootfs/etc/ssh/sshd_config.d/10-archiso.conf"
assert_file_contains "release candidate version is consistent" \
    '0.9-rc1' "$ROOT_DIR/airootfs/opt/linuxre/lib/diagnostics.sh"
if TERM=dumb bash "$ROOT_DIR/airootfs/opt/linuxre/linuxre" </dev/null >/dev/null 2>&1; then
    pass_test "main menu exits cleanly on end-of-input"
else
    fail_test "main menu exits cleanly on end-of-input"
fi

cleanup
assert_true "cleanup does not remove the caller's TMP directory" \
    test -f "$TMP/sentinel"

assert_file_contains "cleanup trap preserves primary status" 'trap cleanup_on_exit EXIT' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"
assert_file_contains "report failure blocks PASS" 'required report could not be written' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"
assert_file_contains "repair report chmod failure is fatal" \
    'Unable to restrict repair report permissions' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"
assert_file_contains "full system upgrade requires explicit confirmation" \
    'Run a full target system upgrade before repair' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]

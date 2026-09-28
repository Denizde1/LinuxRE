#!/usr/bin/env bash

set -uo pipefail

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
cp "$ROOT_DIR"/airootfs/opt/linuxre/lib/{common,target,repair,chroot}.sh "$LIB_DIR/"

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
cat > "$BIN_DIR/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'warning: filesystem: 100 total files, 2 missing files'
exit 1
EOF
chmod +x "$BIN_DIR"/*

export PATH="$BIN_DIR:$PATH"
export MNT="$TMP_DIR/mnt"
export TMP="$TMP_DIR/state"
export REPORT_LOG_PATH="$TMP_DIR/report.log"
export REPORT_FILE_PATH="$TMP_DIR/report.txt"
mkdir -p "$MNT" "$TMP"

# The copied libraries use absolute source paths only in repair/chroot.
# Rewrite those paths in the temporary test copy; repository files remain untouched.
sed -i "s#/opt/linuxre/lib#$LIB_DIR#g" \
    "$LIB_DIR"/target.sh "$LIB_DIR"/repair.sh "$LIB_DIR"/chroot.sh

# shellcheck disable=SC1091
source "$LIB_DIR/common.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/target.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/chroot.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/repair.sh"

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

sample_output=$'warning: filesystem: 100 total files, 2 missing files\nwarning: systemd: 120 total files, 1 altered file\nwarning: healthy: 10 total files, 0 missing files\nwarning: unrelated warning text'
packages="$(printf '%s\n' "$sample_output" | parse_pacman_integrity_output)"

assert_true "parser finds multiple damaged packages" test "$packages" = $'filesystem\nsystemd'
if [[ "$packages" != *warning* ]]; then
    pass_test "parser excludes warning as package name"
else
    fail_test "parser excludes warning as package name"
fi

if [[ "$packages" != *healthy* ]]; then
    pass_test "parser excludes healthy package summaries"
else
    fail_test "parser excludes healthy package summaries"
fi

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

linuxre_chroot() {
    return 1
}

if repair_package_integrity >/dev/null 2>&1; then
    fail_test "pacman integrity command failure propagates"
else
    pass_test "pacman integrity command failure propagates"
fi

assert_file_contains "Btrfs library check is read-only" 'btrfs check --readonly' \
    "$ROOT_DIR/airootfs/opt/linuxre/lib/fsck.sh"
assert_file_contains "Btrfs interactive check is read-only" 'btrfs check --readonly' \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/fsck.sh"
if grep -R -- '--repair' "$ROOT_DIR/airootfs/opt/linuxre/lib/fsck.sh" \
    "$ROOT_DIR/airootfs/opt/linuxre/tools/fsck.sh" >/dev/null; then
    fail_test "Btrfs repair remains disabled"
else
    pass_test "Btrfs repair remains disabled"
fi
assert_file_contains "DNS override stays opt-in" 'LINUXRE_DNS' \
    "$ROOT_DIR/airootfs/usr/local/bin/linuxre-dns"
if grep -q '8\.8\.8\.8' "$ROOT_DIR/airootfs/usr/local/bin/linuxre-dns"; then
    fail_test "DNS override no longer hard-codes Google DNS"
else
    pass_test "DNS override no longer hard-codes Google DNS"
fi
assert_file_contains "DNS service waits for network readiness" 'network-online.target' \
    "$ROOT_DIR/airootfs/etc/systemd/system/linuxre-dns.service"

linuxre_chroot() {
    env LC_ALL=C pacman -Qkk 2>&1
}
if verify_package_integrity >/dev/null 2>&1; then
    fail_test "integrity checks respect pacman damage exit codes"
else
    pass_test "integrity checks respect pacman damage exit codes"
fi

assert_file_contains "cleanup trap preserves primary status" 'trap cleanup_on_exit EXIT' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"
assert_file_contains "report failure blocks PASS" 'required report could not be written' \
    "$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))

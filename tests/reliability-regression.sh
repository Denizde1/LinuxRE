#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2329

set -u

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT_DIR/airootfs/opt/linuxre/lib/target.sh"
FSCK="$ROOT_DIR/airootfs/opt/linuxre/lib/fsck.sh"
CHROOT="$ROOT_DIR/airootfs/opt/linuxre/lib/chroot.sh"
REPAIR="$ROOT_DIR/airootfs/opt/linuxre/lib/repair.sh"
AUTOMATIC="$ROOT_DIR/airootfs/opt/linuxre/scripts/automatic-repair.sh"

tests_run=0
tests_failed=0

fail() {
    printf 'not ok - %s\n' "$1"
    tests_failed=$((tests_failed + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    tests_run=$((tests_run + 1))
    if grep -Eq "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    tests_run=$((tests_run + 1))
    if ! grep -Eq "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    tests_run=$((tests_run + 1))
    if [[ "$expected" == "$actual" ]]; then
        pass "$description"
    else
        fail "$description (expected '$expected', got '$actual')"
    fi
}

printf '1..%s\n' 27

# Target ownership and cleanup policy.
assert_contains "$TARGET" \
    'TARGET_ROOT_MOUNTED=0' \
    'target root ownership is explicitly tracked'
assert_contains "$TARGET" \
    'umount "\$MNT"' \
    'root ownership is cleared only after an unmount check'
assert_contains "$TARGET" \
    'failed=1' \
    'target cleanup records independent failures'
assert_contains "$TARGET" \
    'return "\$failed"' \
    'target cleanup returns failure when cleanup fails'
assert_contains "$TARGET" \
    'ACTIVATED_VGS=\("\${ACTIVATED_VGS\[@\]/\$vg}"\)' \
    'successful LVM cleanup removes only the cleaned VG from ownership'
assert_contains "$TARGET" \
    'OPENED_LUKS=\("\${OPENED_LUKS\[@\]/\$mapper}"\)' \
    'successful LUKS cleanup removes only the cleaned mapper from ownership'

# Filesystem verification safety policy.
assert_contains "$FSCK" \
    'btrfs check "\$device"' \
    'Btrfs verification invokes one non-destructive check'
assert_not_contains "$FSCK" \
    'btrfs check .*--repair' \
    'Btrfs automatic repair is absent'
assert_contains "$FSCK" \
    'return "\$verification_status"' \
    'filesystem command status reaches the caller'
assert_contains "$FSCK" \
    'warn "Unsupported filesystem: \$fstype"' \
    'unsupported filesystems are reported as unsupported'

# Chroot cleanup ownership and failure propagation.
assert_contains "$CHROOT" \
    'CHROOT_RUNTIME_MOUNTS=\(\)' \
    'chroot runtime mounts have an ownership list'
assert_contains "$CHROOT" \
    'command -v mountpoint' \
    'chroot cleanup checks required commands'
assert_contains "$CHROOT" \
    'CHROOT_RUNTIME_MOUNTS=\("\${CHROOT_RUNTIME_MOUNTS\[@\]/\$mountpoint_path}"\)' \
    'successful runtime unmount removes only that tracked mount'
assert_contains "$CHROOT" \
    'return "\$failed"' \
    'chroot cleanup returns failure when an unmount fails'
assert_contains "$CHROOT" \
    'restore_dns \|\| cleanup_failed=1' \
    'DNS restoration failures are preserved'

chroot_cleanup_function="$(sed -n '/^cleanup_chroot_mounts() {/,/^}$/p' "$CHROOT")"
failed_cleanup_result="$(
    eval "$chroot_cleanup_function"
    log() { :; }
    warn() { :; }
    mountpoint() { [[ "$2" != /owned-b ]]; }
    umount() { [[ "$2" == /owned-b ]]; }
    CHROOT_RUNTIME_MOUNTS=(/owned-a /owned-b)
    cleanup_chroot_mounts >/dev/null 2>&1
    printf '%s|%s\n' "$?" "${CHROOT_RUNTIME_MOUNTS[*]}" | sed 's/[[:space:]]*$//'
)"
assert_equal '1|/owned-a' "$failed_cleanup_result" \
    'mocked failed unmount preserves ownership and reports failure'

successful_cleanup_result="$(
    eval "$chroot_cleanup_function"
    log() { :; }
    warn() { :; }
    mounted=1
    mountpoint() { ((mounted != 0)); }
    umount() { mounted=0; }
    CHROOT_RUNTIME_MOUNTS=(/owned-a)
    cleanup_chroot_mounts >/dev/null 2>&1
    printf '%s|%s\n' "$?" "${CHROOT_RUNTIME_MOUNTS[*]}"
)"
assert_equal '0|' "$successful_cleanup_result" \
    'mocked successful unmount clears ownership'

# Package integrity parser and command-status behavior.
parser='^[^:[:space:]][^:]*:[[:space:]]+[0-9]+ total files,.*[1-9][0-9]* (missing|altered) files?'
sample_output=$(
    cat <<'EOF'
bash: 154 total files, 0 altered files
filesystem: 100 total files, 2 missing files
linux-firmware: 200 total files, 1 altered file
warning: unrelated text with 2 missing files
EOF
)
packages="$(printf '%s\n' "$sample_output" |
    awk -F: -v pattern="$parser" '$0 ~ pattern { print $1 }' |
    sort -u)"
assert_equal $'filesystem\nlinux-firmware' "$packages" \
    'package parser handles healthy, damaged, and unrelated output'
assert_contains "$REPAIR" \
    'output=.*pacman -Qkk' \
    'package verification captures pacman output'
assert_contains "$REPAIR" \
    'verification_status=\$\?' \
    'package verification captures pacman status independently'
assert_contains "$REPAIR" \
    'if \(\(verification_status != 0\)\)' \
    'package verification rejects command failure before parsing'
assert_contains "$REPAIR" \
    'repair_status=\$\?' \
    'package reinstall status is captured independently'

# Automatic-repair control flow and report handling.
assert_contains "$AUTOMATIC" \
    'prepare_status=\$\?' \
    'automatic repair captures initial target preparation status'
assert_contains "$AUTOMATIC" \
    'exit "\$prepare_status"' \
    'failed target preparation exits before repair stages'
assert_contains "$AUTOMATIC" \
    'cleanup_target_storage \|\| cleanup_failed=1' \
    'automatic repair preserves target cleanup failure'
assert_contains "$AUTOMATIC" \
    'if ! write_repair_report "PASS"' \
    'PASS requires successful report generation'
assert_contains "$AUTOMATIC" \
    'if ! chmod 600 "\$REPORT_FILE_PATH"' \
    'report permission failure is visible and best-effort'

printf '\n%d tests, %d failures\n' "$tests_run" "$tests_failed"
((tests_failed == 0))

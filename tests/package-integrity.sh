#!/usr/bin/env bash

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/../airootfs/opt/linuxre/lib/package.sh"

failures=0

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s (expected %s, got %s)\n' "$description" "$expected" "$actual" >&2
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$description"
    fi
}

healthy_output='filesystem: 22 total files, 0 missing files, 0 altered files'
one_damaged='filesystem: 22 total files, 1 altered file'
multiple_damaged=$'filesystem: 22 total files, 1 altered file\nsystemd: 900 total files, 2 missing files'
valid_names=$'foo-bar@1.2.3-1: 3 total files, 1 altered file\npython-pyaml: 12 total files, 1 missing file'
unexpected=$'warning: database is locked\nnot a package integrity line'

if printf '%s\n' "$healthy_output" | package_integrity_has_problems; then
    printf 'FAIL: healthy output was marked damaged\n' >&2
    failures=$((failures + 1))
else
    printf 'PASS: healthy output remains healthy\n'
fi

assert_equal filesystem "$(printf '%s\n' "$one_damaged" | extract_damaged_packages)" \
    "one damaged package"
assert_equal $'filesystem\nsystemd' "$(printf '%s\n' "$multiple_damaged" | extract_damaged_packages)" \
    "multiple damaged packages"
assert_equal $'foo-bar@1.2.3-1\npython-pyaml' "$(printf '%s\n' "$valid_names" | extract_damaged_packages)" \
    "valid Arch package names"
assert_equal "" "$(printf '%s\n' "$unexpected" | extract_damaged_packages)" \
    "unexpected output is not treated as a package"

if printf '%s\n' "$multiple_damaged" | package_integrity_has_problems; then
    printf 'PASS: damaged output is detected\n'
else
    printf 'FAIL: damaged output was not detected\n' >&2
    failures=$((failures + 1))
fi

exit "$failures"

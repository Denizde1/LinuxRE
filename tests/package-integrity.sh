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

healthy='filesystem: 22 total files, 0 missing files, 0 altered files'
damaged=$'filesystem: 22 total files, 1 altered file\nsystemd: 900 total files, 2 missing files'

if printf '%s\n' "$healthy" | package_integrity_has_problems; then
    printf 'FAIL: healthy output was marked damaged\n' >&2
    failures=$((failures + 1))
else
    printf 'PASS: healthy output remains healthy\n'
fi

assert_equal $'filesystem\nsystemd' "$(printf '%s\n' "$damaged" | extract_damaged_packages)" \
    "affected packages are extracted"

if printf '%s\n' "$damaged" | package_integrity_has_problems; then
    printf 'PASS: damaged output is detected\n'
else
    printf 'FAIL: damaged output was not detected\n' >&2
    failures=$((failures + 1))
fi

exit "$failures"

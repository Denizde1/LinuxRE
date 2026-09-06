#!/usr/bin/env bash

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/../airootfs/opt/linuxre/lib/status.sh"

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

assert_equal PASS "$(calculate_overall_status NOT_REQUIRED 0)" \
    "all checks pass without repair"
assert_equal PASS "$(calculate_overall_status PASS 0)" \
    "initial failure repaired and final verification passes"
assert_equal FAIL "$(calculate_overall_status FAIL 1)" \
    "failed repair remains failed"
assert_equal FAIL "$(calculate_overall_status PASS 1)" \
    "later final verification failure cannot be overwritten by repair success"
assert_equal FAIL "$(calculate_overall_status NOT_REQUIRED 1)" \
    "report generation cannot turn a final failure into success"

exit "$failures"

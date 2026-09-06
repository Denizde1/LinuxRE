#!/usr/bin/env bash

# Calculate the final result from the outcome of repair operations and
# the final verification pass. Initial diagnostic failures are not enough
# to fail a repair when the repaired target verifies successfully.
calculate_overall_status() {
    local repair_result="${1:-NOT_REQUIRED}"
    local final_failed="${2:-1}"

    if [[ "$repair_result" != "FAIL" && "$final_failed" -eq 0 ]]; then
        printf 'PASS\n'
    else
        printf 'FAIL\n'
    fi
}

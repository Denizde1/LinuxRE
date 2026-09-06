#!/usr/bin/env bash

package_integrity_has_problems() {
    awk '
        /^[[:alnum:]@._+:-]+:/ &&
        /(^|,)[[:space:]]*[1-9][0-9]*[[:space:]]+(missing|altered)[[:space:]]+files?/ {
            found = 1
        }
        END { exit !found }
    '
}

extract_damaged_packages() {
    awk -F: '
        /^[[:alnum:]@._+:-]+:/ &&
        /(^|,)[[:space:]]*[1-9][0-9]*[[:space:]]+(missing|altered)[[:space:]]+files?/ {
            package = $1
            sub(/^[[:space:]]+/, "", package)
            sub(/[[:space:]]+$/, "", package)
            print package
        }
    ' | sort -u
}

#!/usr/bin/env bash

set -uo pipefail

imaging_output_path_is_safe() {
    local path="$1"
    local links

    if [[ -L "$path" ]]; then
        printf 'Error: Refusing to use a symbolic link as an image destination: %s\n' "$path" >&2
        return 1
    fi

    if [[ -e "$path" ]]; then
        links="$(stat -c '%h' -- "$path" 2>/dev/null)" || return 1
        if [[ "$links" != "1" ]]; then
            printf 'Error: Refusing to overwrite a multiply-linked image destination: %s\n' "$path" >&2
            return 1
        fi
    fi

    if [[ -e "$path" && ! -f "$path" ]]; then
        printf 'Error: Image destination must be a regular file: %s\n' "$path" >&2
        return 1
    fi

    return 0
}

imaging_device_tree() {
    local device="$1"
    local tree

    command -v lsblk >/dev/null 2>&1 || return 2
    tree="$(lsblk --list --noheadings --paths --output NAME "$device" 2>/dev/null)" || return 2
    [[ -n "$tree" ]] || return 2
    printf '%s\n' "$tree"
}

imaging_device_is_mounted() {
    local device="$1"
    local tree
    local node

    command -v findmnt >/dev/null 2>&1 || return 2
    tree="$(imaging_device_tree "$device")" || return 2

    while IFS= read -r node; do
        [[ -n "$node" ]] || continue
        if findmnt --noheadings --raw --source "$node" >/dev/null 2>&1; then
            return 0
        fi
    done <<< "$tree"

    return 1
}

imaging_device_in_tree() {
    local candidate="$1"
    local device="$2"
    local tree
    local node
    local candidate_real
    local node_real

    command -v lsblk >/dev/null 2>&1 || return 2
    command -v readlink >/dev/null 2>&1 || return 2
    tree="$(lsblk --inverse --list --noheadings --paths --output NAME "$device" 2>/dev/null)" || return 2
    [[ -n "$tree" ]] || return 2

    candidate_real="$(readlink -f -- "$candidate" 2>/dev/null)" || candidate_real="$candidate"

    while IFS= read -r node; do
        [[ -n "$node" ]] || continue
        node_real="$(readlink -f -- "$node" 2>/dev/null)" || node_real="$node"
        [[ "$candidate_real" == "$node_real" ]] && return 0
    done <<< "$tree"

    return 1
}

imaging_devices_overlap() {
    local source="$1"
    local target="$2"
    local status

    if imaging_device_in_tree "$source" "$target"; then
        return 0
    else
        status=$?
        ((status == 2)) && return 2
    fi

    if imaging_device_in_tree "$target" "$source"; then
        return 0
    else
        status=$?
        ((status == 2)) && return 2
    fi

    return 1
}

imaging_map_path() {
    local operation="$1"
    local map_path
    local links

    case "$operation" in
        create)
            map_path="${3:-}.map"
            ;;
        restore)
            map_path="${2:-}.restore.map"
            ;;
        clone)
            map_path="${4:-}"
            ;;
        *)
            printf 'Error: Unknown ddrescue map operation: %s\n' "$operation" >&2
            return 1
            ;;
    esac

    if [[ -z "$map_path" ]]; then
        printf 'Error: A ddrescue mapfile path is required.\n' >&2
        return 1
    fi

    if [[ -L "$map_path" || ( -e "$map_path" && ! -f "$map_path" ) ]]; then
        printf 'Error: Refusing to use an unsafe ddrescue mapfile: %s\n' "$map_path" >&2
        return 1
    fi

    if [[ -e "$map_path" ]]; then
        links="$(stat -c '%h' -- "$map_path" 2>/dev/null)" || return 1
        if [[ "$links" != "1" ]]; then
            printf 'Error: Refusing to use a multiply-linked ddrescue mapfile: %s\n' "$map_path" >&2
            return 1
        fi
    fi

    printf '%s\n' "$map_path"
}

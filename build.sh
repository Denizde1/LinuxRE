#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE_DIR="$SCRIPT_DIR"
OUTPUT_ROOT="${OUTPUT_DIR:-${HOME:-$PROFILE_DIR}/linuxre-out}"
LOG_FILE=""
CHECKSUM_TMP=""

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local status=$?
    local line="${BASH_LINENO[0]:-unknown}"

    trap - ERR
    printf 'Build failed at line %s (exit status %s).\n' "$line" "$status" >&2
    if [[ -n "$LOG_FILE" ]]; then
        printf 'Build log: %s\n' "$LOG_FILE" >&2
    fi
    exit "$status"
}

on_signal() {
    local status="$1"

    trap - INT TERM HUP
    printf 'Build interrupted (exit status %s).\n' "$status" >&2
    if [[ -n "$LOG_FILE" ]]; then
        printf 'Build log: %s\n' "$LOG_FILE" >&2
    fi
    exit "$status"
}

cleanup_temporary_file() {
    if [[ -n "$CHECKSUM_TMP" && -f "$CHECKSUM_TMP" ]]; then
        rm -f -- "$CHECKSUM_TMP" ||
            printf 'Warning: could not remove temporary checksum file: %s\n' "$CHECKSUM_TMP" >&2
    fi
}

trap on_error ERR
trap cleanup_temporary_file EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_privileged() {
    if (( EUID == 0 )); then
        "$@"
    else
        sudo "$@"
    fi
}

check_host() {
    [[ -r /etc/os-release ]] || die "Cannot identify the operating system (/etc/os-release is unavailable)."
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != arch && " ${ID_LIKE:-} " != *" arch "* ]]; then
        die "This profile must be built on Arch Linux or an Arch-based system."
    fi

    [[ "$(uname -m)" == x86_64 ]] || die "This profile requires an x86_64 build host."
}

check_profile() {
    local path

    for path in \
        "$PROFILE_DIR/profiledef.sh" \
        "$PROFILE_DIR/packages.x86_64" \
        "$PROFILE_DIR/pacman.conf" \
        "$PROFILE_DIR/bootstrap_packages" \
        "$PROFILE_DIR/airootfs" \
        "$PROFILE_DIR/efiboot"; do
        [[ -r "$path" ]] || die "Required profile file or directory is missing or unreadable: $path"
    done

    [[ -s "$PROFILE_DIR/profiledef.sh" ]] || die "profiledef.sh is empty."
    grep -Eq '^[[:space:]]*buildmodes=.*iso' "$PROFILE_DIR/profiledef.sh" ||
        die "profiledef.sh does not enable the ISO build mode."
    [[ -s "$PROFILE_DIR/packages.x86_64" ]] || die "packages.x86_64 is empty."
    awk 'NF && $1 !~ /^#/ { found=1 } END { exit !found }' "$PROFILE_DIR/packages.x86_64" ||
        die "packages.x86_64 does not contain any package names."
    grep -Eq '^[[:space:]]*\[core\][[:space:]]*$' "$PROFILE_DIR/pacman.conf" ||
        die "pacman.conf does not define the [core] repository."
    grep -Eq '^[[:space:]]*\[extra\][[:space:]]*$' "$PROFILE_DIR/pacman.conf" ||
        die "pacman.conf does not define the [extra] repository."
}

ensure_archiso() {
    if pacman -Q archiso >/dev/null 2>&1 && command -v mkarchiso >/dev/null 2>&1; then
        printf 'Using %s\n' "$(pacman -Q archiso)"
        return
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        die "archiso is missing and pacman is unavailable; install archiso before building."
    fi
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 ||
            die "archiso is missing. Install it with 'sudo pacman -S --needed archiso' (sudo is unavailable)."
        [[ -t 0 ]] ||
            die "archiso is missing. Run 'sudo pacman -S --needed archiso' interactively, then rerun this script."
        printf 'archiso is not installed; requesting permission to install it (no full system upgrade will be run).\n'
        sudo -v
    else
        printf 'archiso is not installed; pacman will ask for confirmation before installing it.\n'
    fi

    local install_status=0
    if run_privileged pacman -S --needed archiso; then
        :
    else
        install_status=$?
        printf "Error: installing archiso failed (exit status %s). No full system upgrade was run.\n" \
            "$install_status" >&2
        exit "$install_status"
    fi

    command -v mkarchiso >/dev/null 2>&1 ||
        die "archiso installation completed, but mkarchiso is still unavailable."
    pacman -Q archiso
}

get_mkarchiso_options() {
    local help_output

    if ! help_output="$(mkarchiso -h 2>&1)"; then
        die "Could not read mkarchiso help to verify supported build options."
    fi

    for option in '-v' '-w' '-o'; do
        grep -Eq "^[[:space:]]*${option//-/\\-}([[:space:]]|$)" <<< "$help_output" ||
            die "Installed mkarchiso does not support the required $option option."
    done

    if grep -Eq '^[[:space:]]*-r([[:space:]]|$)' <<< "$help_output"; then
        CLEAN_WORK_OPTION=(-r)
    else
        CLEAN_WORK_OPTION=()
        printf 'Note: this mkarchiso version has no -r option; its work directory will be kept.\n'
    fi
}

check_disk_space() {
    local available_kib
    local minimum_kib=$((12 * 1024 * 1024))

    available_kib="$(df -Pk -- "$OUTPUT_ROOT" | awk 'END { print $4 }')"
    [[ "$available_kib" =~ ^[0-9]+$ ]] || die "Could not determine free space for $OUTPUT_ROOT."
    if (( available_kib < minimum_kib )); then
        die "At least 12 GiB of free space is required on the output filesystem; only $((available_kib / 1024 / 1024)) GiB is available at $OUTPUT_ROOT."
    fi
}

main() {
    local required_tools=(awk df file find grep mktemp mv pacman rm sha256sum stat tee uname)
    local tool
    local run_dir
    local work_dir
    local iso_file
    local file_type
    local checksum_file
    local iso_size
    local available_options=()
    local -a CLEAN_WORK_OPTION=()
    local -a iso_files=()

    (($# == 0)) || die "Usage: $0"

    check_host

    for tool in "${required_tools[@]}"; do
        require_command "$tool"
    done
    check_profile

    mkdir -p -- "$OUTPUT_ROOT"
    OUTPUT_ROOT="$(cd -- "$OUTPUT_ROOT" && pwd -P)"
    check_disk_space
    ensure_archiso
    get_mkarchiso_options

    if (( EUID != 0 )); then
        require_command sudo
        sudo -v
    fi

    run_dir="$(mktemp -d -- "$OUTPUT_ROOT/linuxre-build.XXXXXXXX")"
    LOG_FILE="$run_dir/build.log"
    : > "$LOG_FILE"
    work_dir="$(mktemp -d -- "$OUTPUT_ROOT/.linuxre-work.XXXXXXXX")"

    available_options=(-v -w "$work_dir" -o "$run_dir")
    printf 'Building profile %s\nOutput directory: %s\n' "$PROFILE_DIR" "$run_dir"
    printf 'Command: mkarchiso'
    printf ' %q' "${available_options[@]}" "${CLEAN_WORK_OPTION[@]}" "$PROFILE_DIR"
    printf '\nBuild log: %s\n' "$LOG_FILE"

    run_privileged mkarchiso \
        "${available_options[@]}" \
        "${CLEAN_WORK_OPTION[@]}" \
        "$PROFILE_DIR" 2>&1 | tee -a "$LOG_FILE"

    mapfile -d '' -t iso_files < <(find "$run_dir" -maxdepth 1 -type f -name '*.iso' -print0)
    ((${#iso_files[@]} == 1)) ||
        die "Expected exactly one ISO in $run_dir, found ${#iso_files[@]}. See the build log."

    iso_file="${iso_files[0]}"
    [[ -s "$iso_file" && -r "$iso_file" ]] ||
        die "The generated ISO is empty or unreadable: $iso_file"
    file_type="$(file --brief -- "$iso_file")"
    [[ "$file_type" == *"ISO 9660"* ]] ||
        die "The generated file does not appear to be an ISO 9660 image: $file_type"

    checksum_file="$iso_file.sha256"
    CHECKSUM_TMP="$(mktemp -- "$run_dir/.sha256.XXXXXXXX")"
    sha256sum -- "$iso_file" > "$CHECKSUM_TMP"
    mv -- "$CHECKSUM_TMP" "$checksum_file"
    CHECKSUM_TMP=""
    sha256sum --check "$checksum_file"

    iso_size="$(stat -c '%s' -- "$iso_file")"
    case "$work_dir" in
        "$OUTPUT_ROOT"/.linuxre-work.*) ;;
        *) die "Refusing to remove an unexpected work directory: $work_dir" ;;
    esac
    if ! run_privileged rm -rf -- "$work_dir"; then
        printf 'Warning: could not remove temporary work directory: %s\n' "$work_dir" >&2
    fi

    printf '\nISO: %s\nSize: %s bytes\nSHA-256 file: %s\n' \
        "$iso_file" "$iso_size" "$checksum_file"
}

main "$@"

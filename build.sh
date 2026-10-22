#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE_DIR="$SCRIPT_DIR"
OUTPUT_ROOT="${OUTPUT_DIR:-${HOME:-$PROFILE_DIR}/linuxre-out}"
LOG_FILE=""
CHECKSUM_TMP=""
WORK_DIR=""
ISO_NAME=""
BUILD_ARCH=""
BUILD_CACHE_DIRS=()

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

report_preserved_artifacts() {
    if [[ -n "$LOG_FILE" ]]; then
        printf 'Build log: %s\n' "$LOG_FILE" >&2
    fi
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        printf 'Working directory retained for diagnosis: %s\n' "$WORK_DIR" >&2
    fi
}

on_error() {
    local status=$?
    local line="${BASH_LINENO[0]:-unknown}"

    trap - ERR
    printf 'Build failed at line %s (exit status %s).\n' "$line" "$status" >&2
    report_preserved_artifacts
    exit "$status"
}

on_signal() {
    local status="$1"

    trap - INT TERM HUP
    printf 'Build interrupted (exit status %s).\n' "$status" >&2
    report_preserved_artifacts
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

    BUILD_ARCH="$(uname -m)"
    [[ "$BUILD_ARCH" == x86_64 ]] || die "This profile requires an x86_64 build host."
}

check_profile() {
    local path
    local profile_iso_name

    for path in \
        "$PROFILE_DIR/profiledef.sh" \
        "$PROFILE_DIR/packages.x86_64" \
        "$PROFILE_DIR/pacman.conf" \
        "$PROFILE_DIR/airootfs" \
        "$PROFILE_DIR/efiboot"; do
        [[ -r "$path" ]] || die "Required profile file or directory is missing or unreadable: $path"
    done

    [[ -f "$PROFILE_DIR/profiledef.sh" && -s "$PROFILE_DIR/profiledef.sh" ]] ||
        die "profiledef.sh is missing or empty."
    [[ -f "$PROFILE_DIR/packages.x86_64" && -s "$PROFILE_DIR/packages.x86_64" ]] ||
        die "packages.x86_64 is missing or empty."
    [[ -f "$PROFILE_DIR/pacman.conf" ]] || die "pacman.conf is missing."
    [[ -d "$PROFILE_DIR/airootfs" && -d "$PROFILE_DIR/efiboot" ]] ||
        die "airootfs and efiboot must be profile directories."

    if ! profile_iso_name="$(
        bash -Eeuo pipefail -c '
            declare -A file_permissions=()
            source "$1"
            [[ " ${buildmodes[*]-} " == *" iso "* ]]
            [[ " ${bootmodes[*]-} " == *" uefi.systemd-boot "* ]]
            [[ -n "${iso_name:-}" ]]
            printf "%s\n" "$iso_name"
        ' bash "$PROFILE_DIR/profiledef.sh" 2>/dev/null
    )"; then
        die "profiledef.sh must be valid Bash and enable the ISO and uefi.systemd-boot modes."
    fi
    ISO_NAME="$profile_iso_name"

    [[ -r "$PROFILE_DIR/efiboot/loader/loader.conf" ]] ||
        die "The uefi.systemd-boot profile requires efiboot/loader/loader.conf."
    [[ -n "$(find "$PROFILE_DIR/efiboot/loader/entries" -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null)" ]] ||
        die "The uefi.systemd-boot profile requires at least one efiboot loader entry."

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
    local option

    if ! help_output="$(mkarchiso -h 2>&1)"; then
        die "Could not read mkarchiso help to verify supported build options."
    fi

    for option in '-v' '-w' '-o'; do
        awk -v option="$option" '$1 == option { found=1 } END { exit !found }' <<< "$help_output" ||
            die "Installed mkarchiso does not support the required $option option."
    done
}

get_build_cache_dirs() {
    local system_cache_dirs
    local profile_cache_dirs
    local selected_cache_dirs

    system_cache_dirs="$(pacman-conf CacheDir | tr '\n' ' ')" ||
        die "Could not read the system pacman CacheDir."
    profile_cache_dirs="$(pacman-conf --config "$PROFILE_DIR/pacman.conf" CacheDir | tr '\n' ' ')" ||
        die "Could not read the profile pacman CacheDir."

    if [[ "$profile_cache_dirs" != "/var/cache/pacman/pkg" &&
          "$system_cache_dirs" != "$profile_cache_dirs" ]]; then
        selected_cache_dirs="$profile_cache_dirs"
    else
        selected_cache_dirs="$system_cache_dirs"
    fi
    read -r -a BUILD_CACHE_DIRS <<< "$selected_cache_dirs"
    ((${#BUILD_CACHE_DIRS[@]} > 0)) || die "No pacman package cache directory was configured."
}

check_free_space_at() {
    local path="$1"
    local existing_path="$path"
    local available_kib
    local minimum_kib="$2"

    while [[ ! -d "$existing_path" && "$existing_path" != / ]]; do
        existing_path="${existing_path%/*}"
        [[ -n "$existing_path" ]] || existing_path=/
    done
    [[ -d "$existing_path" ]] || die "Could not find a filesystem for $path."

    available_kib="$(df -Pk -- "$existing_path" | awk 'END { print $4 }')"
    [[ "$available_kib" =~ ^[0-9]+$ ]] || die "Could not determine free space for $path."
    if (( available_kib < minimum_kib )); then
        die "At least ${MIN_BUILD_GIB} GiB of free space is required for the build; only $((available_kib / 1024 / 1024)) GiB is available on the filesystem containing $path."
    fi
}

check_disk_space() {
    local minimum_gib="${MIN_BUILD_GIB:-20}"
    local minimum_kib
    local cache_dir

    [[ "$minimum_gib" =~ ^[1-9][0-9]{0,5}$ ]] ||
        die "MIN_BUILD_GIB must be a positive integer no greater than 999999."
    minimum_kib=$((10#$minimum_gib * 1024 * 1024))
    MIN_BUILD_GIB="$minimum_gib"

    check_free_space_at "$OUTPUT_ROOT" "$minimum_kib"
    for cache_dir in "${BUILD_CACHE_DIRS[@]}"; do
        check_free_space_at "$cache_dir" "$minimum_kib"
    done
}

main() {
    local required_tools=(awk bash chmod df file find grep mktemp mv pacman pacman-conf rm sha256sum stat tee tr uname)
    local tool
    local run_dir
    local iso_file
    local file_type
    local checksum_file
    local iso_size
    local build_status
    local available_options=()
    local -a iso_files=()

    (($# == 0)) || die "Usage: $0"

    check_host

    for tool in "${required_tools[@]}"; do
        require_command "$tool"
    done
    check_profile

    mkdir -p -- "$OUTPUT_ROOT"
    OUTPUT_ROOT="$(cd -- "$OUTPUT_ROOT" && pwd -P)"
    ensure_archiso
    get_mkarchiso_options
    get_build_cache_dirs
    check_disk_space

    if (( EUID != 0 )); then
        require_command sudo
        sudo -v
    fi

    run_dir="$(mktemp -d -- "$OUTPUT_ROOT/linuxre-build.XXXXXXXX")"
    LOG_FILE="$run_dir/build.log"
    : > "$LOG_FILE"
    WORK_DIR="$(mktemp -d -- "$OUTPUT_ROOT/.linuxre-work.XXXXXXXX")"

    available_options=(-v -w "$WORK_DIR" -o "$run_dir")
    printf 'Building profile %s\nOutput directory: %s\n' "$PROFILE_DIR" "$run_dir"
    printf 'Command: mkarchiso'
    printf ' %q' "${available_options[@]}" "$PROFILE_DIR"
    printf '\nBuild log: %s\n' "$LOG_FILE"

    if run_privileged mkarchiso \
        "${available_options[@]}" \
        "$PROFILE_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        :
    else
        build_status=$?
        printf 'mkarchiso failed (exit status %s).\n' "$build_status" >&2
        report_preserved_artifacts
        exit "$build_status"
    fi

    mapfile -d '' -t iso_files < <(find "$run_dir" -maxdepth 1 -type f -name '*.iso' -print0)
    ((${#iso_files[@]} == 1)) ||
        die "Expected exactly one ISO in $run_dir, found ${#iso_files[@]}. See the build log."

    iso_file="${iso_files[0]}"
    [[ "${iso_file##*/}" == "$ISO_NAME"-*-"$BUILD_ARCH".iso ]] ||
        die "Unexpected ISO filename: ${iso_file##*/} (expected $ISO_NAME-<version>-$BUILD_ARCH.iso)."
    run_privileged chmod a+r -- "$iso_file"
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
    case "$WORK_DIR" in
        "$OUTPUT_ROOT"/.linuxre-work.*) ;;
        *) die "Refusing to remove an unexpected work directory: $WORK_DIR" ;;
    esac
    if ! run_privileged rm -rf -- "$WORK_DIR"; then
        printf 'Warning: could not remove temporary work directory: %s\n' "$WORK_DIR" >&2
    fi
    WORK_DIR=""

    printf '\nISO: %s\nSize: %s bytes\nSHA-256 file: %s\n' \
        "$iso_file" "$iso_size" "$checksum_file"
}

main "$@"

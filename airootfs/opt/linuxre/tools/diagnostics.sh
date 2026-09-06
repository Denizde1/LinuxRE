#!/usr/bin/env bash

set -uo pipefail

# shellcheck disable=SC1091
source /opt/linuxre/lib/system-info.sh
# shellcheck disable=SC1091
source /opt/linuxre/lib/diagnostics.sh

while true; do
    clear
    printf '%s\n\n' "Read-only Diagnostics"
    printf '%s\n' "  1) System information [READ ONLY]"
    printf '%s\n' "  2) Diagnostic scan [READ ONLY]"
    printf '%s\n\n' "  0) Back"
    read -r -p "Select an option: " choice

    case "$choice" in
        1) clear; show_system_information; read -r -p "Press Enter to continue..." _ ;;
        2) clear; run_diagnostic_scan; read -r -p "Press Enter to continue..." _ ;;
        0) exit 0 ;;
        *) printf '%s\n' "Invalid option."; sleep 1 ;;
    esac
done

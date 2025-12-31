#!/usr/bin/env bash
#
# wifi-helper.sh
#
# Menu-driven and flag-driven Wi‑Fi helper for macOS:
# - Detect Wi‑Fi interface (en0, en1, etc.)
# - List preferred Wi‑Fi networks (SSIDs)
# - Show password for a chosen SSID (via Keychain)
# - Show example command for adding a network with security type
#
# New:
# - OS detection and error handling (ERR trap)
# - Non-interactive mode (--non-interactive + --action ...)
# - Optional JSON output (--json)
# - Optional output file redirection (--output FILE)
#
# NOTE:
# - macOS will prompt for permission to access each password in Keychain.
# - Intended for administrative / troubleshooting use on YOUR Mac.

set -euo pipefail

SCRIPT_NAME="${0##*/}"
MIN_MACOS_VERSION="10.10"

# Global flags (defaults)
NON_INTERACTIVE=false
ACTION=""           # list-ssids | show-password
TARGET_SSID=""
OUTPUT_JSON=false
OUTPUT_FILE=""

#-----------------------------
# Error handling
#-----------------------------

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  echo "[$SCRIPT_NAME] ERROR: Command failed with exit code $exit_code at line $line_no: ${BASH_COMMAND:-unknown}" >&2
  echo "[$SCRIPT_NAME] Hint: Re-run with: bash -x $SCRIPT_NAME ..." >&2
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

err() {
  printf "[$SCRIPT_NAME] ERROR: %s\n" "$*" >&2
}

warn() {
  printf "[$SCRIPT_NAME] WARNING: %s\n" "$*" >&2
}

pause() {
  read -r -p "Press Enter to continue..." _
}

#-----------------------------
# Version helpers
#-----------------------------

version_ge() {
  local v1="$1"
  local v2="$2"
  if [[ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]; then
    return 0
  else
    return 1
  fi
}

#-----------------------------
# OS detection
#-----------------------------

check_os() {
  local uname_out
  uname_out=$(uname -s 2>/dev/null || echo "unknown")

  case "$uname_out" in
    Darwin)
      ;;
    *)
      err "Unsupported OS: $uname_out. This script only works on macOS."
      exit 1
      ;;
  esac
}

get_macos_version() {
  if ! command -v sw_vers >/dev/null 2>&1; then
    warn "sw_vers not found; cannot determine macOS version."
    echo "unknown"
    return 0
  fi

  sw_vers -productVersion 2>/dev/null || echo "unknown"
}

check_macos_version() {
  local os_ver
  os_ver=$(get_macos_version)

  if [[ "$os_ver" == "unknown" ]]; then
    warn "macOS version is unknown; continuing, but some features may behave unexpectedly."
    return 0
  fi

  if ! version_ge "$os_ver" "$MIN_MACOS_VERSION"; then
    warn "Detected macOS $os_ver, below recommended minimum $MIN_MACOS_VERSION. Continuing anyway."
  fi
}

#-----------------------------
# Wi‑Fi helpers
#-----------------------------

detect_wifi_device() {
  if ! command -v networksetup >/dev/null 2>&1; then
    err "networksetup not found. Are you on macOS with command-line tools installed?"
    exit 2
  fi

  local dev
  dev=$(networksetup -listallhardwareports \
    | awk '/Wi-Fi|AirPort/ {getline; if ($1=="Device:") print $2}')

  if [[ -z "${dev:-}" ]]; then
    warn "Could not auto-detect Wi‑Fi interface via networksetup -listallhardwareports."
    read -r -p "Please enter Wi‑Fi interface manually (e.g. en0, en1): " dev
    if [[ -z "${dev:-}" ]]; then
      err "No interface provided. Cannot proceed."
      exit 3
    fi
  fi

  echo "$dev"
}

list_preferred_networks_raw() {
  local wifi_dev="$1"
  networksetup -listpreferredwirelessnetworks "$wifi_dev"
}

get_ssid_array() {
  local wifi_dev="$1"
  local output
  output=$(list_preferred_networks_raw "$wifi_dev") || return 1

  printf '%s\n' "$output" \
    | sed '1d' \
    | sed 's/^[[:space:]]*//' \
    | awk 'NF > 0'
}

show_wifi_password() {
  local ssid="$1"

  if [[ -z "$ssid" ]]; then
    err "SSID is empty; cannot look up password."
    return 1
  fi

  if ! command -v security >/dev/null 2>&1; then
    err "security CLI not found. Keychain access is unavailable."
    return 2
  fi

  local pw
  if ! pw=$(security find-generic-password -wa "$ssid" 2>/dev/null); then
    if ! pw=$(security find-internet-password -wa "$ssid" 2>/dev/null); then
      err "Could not retrieve password for \"$ssid\" (not found or access denied)."
      return 3
    fi
  fi

  printf '%s\n' "$pw"
}

show_add_network_example() {
  local wifi_dev="$1"

  cat <<EOF
Example: add a preferred Wi‑Fi network with security type using networksetup

  networksetup -addpreferredwirelessnetworkatindex \\
    $wifi_dev "YOUR_SSID" 0 WPA2 "your_password"

Fields:
  - Interface: $wifi_dev
  - SSID: YOUR_SSID
  - Index: 0 (top priority; adjust as needed)
  - Security type: WPA2 (or WPA3, WPA2/WPA3, WEP, etc.)

EOF
}

#-----------------------------
# Output helpers (text/JSON + file)
#-----------------------------

ensure_output_file() {
  if [[ -n "$OUTPUT_FILE" ]]; then
    # Ensure directory exists; don't fail if parent is current directory.
    mkdir -p "$(dirname "$OUTPUT_FILE")"
  fi
}

emit_line() {
  # Emit a single line to stdout and optionally append to log file.
  local line="$1"
  echo "$line"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$line" >>"$OUTPUT_FILE"
  fi
}

emit_block() {
  # Emit a multi-line block.
  local block="$1"
  printf '%s\n' "$block"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$block" >>"$OUTPUT_FILE"
  fi
}

json_escape() {
  # Minimal JSON string escaper (quotes and backslashes).
  # For serious JSON work, jq is preferred, but this keeps dependencies minimal. [web:71][web:80]
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

#-----------------------------
# Menu (interactive)
#-----------------------------

menu_show_password_for_ssid() {
  local wifi_dev="$1"
  local -a ssids
  local PS3
  local choice

  mapfile -t ssids < <(get_ssid_array "$wifi_dev")

  if ((${#ssids[@]} == 0)); then
    err "No preferred Wi‑Fi networks found for $wifi_dev."
    return 1
  fi

  echo
  echo "Select a Wi‑Fi network to show its password:"
  PS3="Enter choice (or 0 to cancel): "

  select choice in "${ssids[@]}"; do
    if [[ -z "${REPLY:-}" ]]; then
      err "No selection made; returning to main menu."
      break
    fi

    if [[ "$REPLY" == "0" ]]; then
      echo "Cancelled."
      break
    fi

    if [[ -n "$choice" ]]; then
      local pw
      pw=$(show_wifi_password "$choice") || return $?
      emit_line "Password for \"$choice\": $pw"
      break
    else
      echo "Invalid selection. Try again."
    fi
  done
}

interactive_menu() {
  local wifi_dev="$1"

  echo "Using Wi‑Fi interface: $wifi_dev"
  echo

  while true; do
    echo "========== Wi‑Fi Helper Menu =========="
    echo "1) List all preferred Wi‑Fi networks"
    echo "2) Select a Wi‑Fi network and show its password"
    echo "3) Show example command for adding a preferred network with security type"
    echo "4) Change Wi‑Fi interface (current: $wifi_dev)"
    echo "0) Exit"
    echo "======================================="
    read -r -p "Enter choice: " choice

    case "$choice" in
      1)
        local out
        out=$(list_preferred_networks_raw "$wifi_dev")
        emit_block "$out"
        pause
        ;;
      2)
        menu_show_password_for_ssid "$wifi_dev"
        pause
        ;;
      3)
        local example
        example=$(show_add_network_example "$wifi_dev")
        emit_block "$example"
        pause
        ;;
      4)
        wifi_dev=$(detect_wifi_device)
        echo "Now using Wi‑Fi interface: $wifi_dev"
        pause
        ;;
      0)
        echo "Goodbye."
        exit 0
        ;;
      *)
        echo "Invalid choice. Please try again."
        ;;
    esac

    echo
  done
}

#-----------------------------
# Non-interactive actions
#-----------------------------

run_non_interactive() {
  local wifi_dev="$1"

  case "$ACTION" in
    list-ssids)
      local -a ssids
      mapfile -t ssids < <(get_ssid_array "$wifi_dev")

      if [[ "$OUTPUT_JSON" == "true" ]]; then
        # JSON array of objects: [{ "ssid": "..." }, ...]
        local json="["
        local first=true
        for s in "${ssids[@]}"; do
          $first || json+=","
          first=false
          json+="{\"ssid\":\"$(json_escape "$s")\"}"
        done
        json+="]"
        emit_line "$json"
      else
        # Plain text list
        for s in "${ssids[@]}"; do
          emit_line "$s"
        done
      fi
      ;;

    show-password)
      if [[ -z "$TARGET_SSID" ]]; then
        err "--action show-password requires --ssid <NAME>"
        exit 4
      fi
      local pw
      pw=$(show_wifi_password "$TARGET_SSID")

      if [[ "$OUTPUT_JSON" == "true" ]]; then
        # Single object: {"ssid":"...", "password":"..."}
        local json
        json=$(printf '{"ssid":"%s","password":"%s"}' \
          "$(json_escape "$TARGET_SSID")" "$(json_escape "$pw")")
        emit_line "$json"
      else
        emit_line "SSID: $TARGET_SSID"
        emit_line "Password: $pw"
      fi
      ;;

    *)
      err "Unknown or missing --action. Use list-ssids or show-password."
      exit 5
      ;;
  esac
}

#-----------------------------
# CLI parsing
#-----------------------------

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Interactive mode (default):
  $SCRIPT_NAME

Non-interactive examples:
  # List SSIDs in plain text
  $SCRIPT_NAME --non-interactive --action list-ssids

  # List SSIDs as JSON and write to file
  $SCRIPT_NAME --non-interactive --action list-ssids --json --output ssids.json

  # Show password for a given SSID in plain text
  $SCRIPT_NAME --non-interactive --action show-password --ssid "MyWiFi"

  # Show password as JSON and log to file
  $SCRIPT_NAME --non-interactive --action show-password --ssid "MyWiFi" --json --output wifi-creds.json

Options:
  -h, --help            Show this help and exit
      --non-interactive Run a single action and exit (no menu)
      --action ACTION   Action to perform (list-ssids | show-password)
      --ssid NAME       SSID to operate on (used with show-password)
      --json            Output JSON instead of plain text
      --output FILE     Append output to FILE

EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --action)
        ACTION="${2:-}"
        shift 2
        ;;
      --ssid)
        TARGET_SSID="${2:-}"
        shift 2
        ;;
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --output)
        OUTPUT_FILE="${2:-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

#-----------------------------
# Main
#-----------------------------

main() {
  check_os
  check_macos_version

  parse_args "$@"
  ensure_output_file

  local wifi_dev
  wifi_dev=$(detect_wifi_device)

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    run_non_interactive "$wifi_dev"
  else
    interactive_menu "$wifi_dev"
  fi
}

main "$@"


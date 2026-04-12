#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-uefi}"

list_usbserial() {
  ls /dev/cu.usbserial-* 2>/dev/null || true
}

list_usbmodem() {
  ls /dev/cu.usbmodem* 2>/dev/null || true
}

run_console() {
  local device="$1"
  local baud="$2"

  if command -v tio >/dev/null 2>&1; then
    exec tio -b "$baud" "$device"
  else
    if ! command -v screen >/dev/null 2>&1; then
      echo "Neither tio nor screen is installed. Install one of them first." >&2
      exit 1
    fi
    exec screen "$device" "$baud"
  fi
}

case "$MODE" in
  list)
    echo "Debug-USB serial devices:"
    list_usbserial | nl || true
    echo
    echo "OEM-config usbmodem devices:"
    list_usbmodem | nl || true
    echo
    echo "UEFI/Linux uses the second usbserial device; OEM-config uses the first usbmodem device."
    exit 0
    ;;
  uefi)
    mapfile -t devs < <(list_usbserial)
    if [[ ${#devs[@]} -lt 2 ]]; then
      echo "Need at least two /dev/cu.usbserial-* devices. Thor Debug-USB usually exposes four."
      exit 1
    fi
    printf '\e[8;61;242t'
    echo "Opening ${devs[1]} at 9600 baud (factory UEFI path)"
    run_console "${devs[1]}" 9600
    ;;
  linux)
    mapfile -t devs < <(list_usbserial)
    if [[ ${#devs[@]} -lt 2 ]]; then
      echo "Need at least two /dev/cu.usbserial-* devices. Thor Debug-USB usually exposes four."
      exit 1
    fi
    echo "Opening ${devs[1]} at 115200 baud (booted Linux over Debug-USB)"
    run_console "${devs[1]}" 115200
    ;;
  oem-config)
    mapfile -t devs < <(list_usbmodem)
    if [[ ${#devs[@]} -lt 1 ]]; then
      echo "No /dev/cu.usbmodem* device found. Move the cable to Thor USB-C port 5a after the NVMe boot."
      exit 1
    fi
    echo "Opening ${devs[0]} at 115200 baud (oem-config CUI)"
    run_console "${devs[0]}" 115200
    ;;
  *)
    echo "Usage: $0 [uefi|linux|oem-config|list]"
    exit 1
    ;;
esac

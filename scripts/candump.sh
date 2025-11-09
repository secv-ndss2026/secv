#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
#
# my_canperf_cap.sh — GoldVIP: cangen(TX) + candump(RX) -> candump.txt (delta time)
# - Follows my_canperf.sh option names/validations
# - No 'timeout' dependency; simple sleep + kill lifecycle (like GoldVIP scripts)
# - Correct candump filter mask (7FF for 11-bit, 1FFFFFFF for 29-bit)
# - Does NOT run latency.py automatically
#
# Usage example:
#   ./my_canperf_cap.sh -t can0 -r can1 -i 291 -o 291 -g 10 -s 8 -l 5 -D i --out /tmp/candump.txt
#
set -Ee

# Defaults (align with my_canperf.sh semantics)
rx_id=notset
tx_id=notset
can_tx_interface=notset
can_rx_interface=notset
frame_gap_ms=notset
can_frame_data_size=notset
time_gen=notset

payload_random_mode="r"
payload_increment_mode="i"
payload_data="${payload_increment_mode}"

out_file="/tmp/candump.txt"

pid_candump=0
pid_cangen=0

readonly integer_regex="^[0-9]+$"
readonly hex_regex="^[0-9A-Fa-f]+$"
# Valid classic CAN and CAN FD DLC values used by my_canperf.sh
readonly can_dlc_array=("1" "2" "3" "4" "5" "6" "7" "8" "12" "16" "20" "24" "32" "48" "64")

set_trap() {
  trap 'cleanup_and_exit 130' INT
  trap 'echo "An error occurred in $0 at line ${BASH_LINENO[0]}"; cleanup_and_exit 1' ERR
}

cleanup_and_exit() {
  local code="${1:-0}"
  # Stop TX first
  if [[ "${pid_cangen}" -ne 0 ]]; then
    kill "${pid_cangen}" 2>/dev/null || true
    sleep 0.5
    kill -9 "${pid_cangen}" 2>/dev/null || true
  fi
  # Then stop RX
  if [[ "${pid_candump}" -ne 0 ]]; then
    kill "${pid_candump}" 2>/dev/null || true
    sleep 0.5
    kill -9 "${pid_candump}" 2>/dev/null || true
  fi
  # As a last resort, kill by name (busybox systems)
  killall cangen  2>/dev/null || true
  killall candump 2>/dev/null || true
  exit "${code}"
}

usage() {
  cat <<USAGE
Usage: ./$(basename "$0") [options]
  -t | --can-tx <can0|can1>   TX interface
  -r | --can-rx <can0|can1>   RX interface
  -i | --tx-id <0..2047>      TX CAN ID (decimal, standard 11-bit)
  -o | --rx-id <0..536870911> RX CAN ID (decimal; >2047 implies extended 29-bit)
  -g | --gap <ms>             Frame gap (ms)
  -s | --size <bytes|i>       DLC (1..8,12,16,20,24,32,48,64) or 'i'
  -l | --length <sec>         Duration (sec)
  -D | --payload <i|r|HEX>    Payload: i(increment), r(random), HEX (no spaces)
  --out <path>                Output candump path (default: /tmp/candump.txt)
  --log <path>                (alias of --out)
  -h | --help                 Help
Then run:
  python3 latency.py <candump_output.txt>
USAGE
}

check_input() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -g|--gap)      shift; frame_gap_ms="$1"
        [[ "$frame_gap_ms" =~ $integer_regex ]] || { echo "Frame gap must be positive integer"; exit 1; } ;;
      -i|--tx-id)    shift; tx_id="$1"
        [[ "$tx_id" =~ $integer_regex ]] || { echo "TX CAN ID must be positive integer"; exit 1; }
        if [[ -z "$tx_id" || $((tx_id)) -lt 0 || $((tx_id)) -gt 536870911 ]]; then
          echo "TX CAN ID out of range"; exit 1; fi ;;
      -o|--rx-id)    shift; rx_id="$1"
        [[ "$rx_id" =~ $integer_regex ]] || { echo "RX CAN ID must be positive integer"; exit 1; }
        if [[ -z "$rx_id" || $((rx_id)) -lt 0 || $((rx_id)) -gt 536870911 ]]; then
          echo "RX CAN ID out of range"; exit 1; fi ;;
      -t|--can-tx)   shift; can_tx_interface="$1"
        if [[ "$can_tx_interface" != "can0" && "$can_tx_interface" != "can1" ]]; then
          echo "Transmit interface must be can0 or can1"; exit 1; fi ;;
      -r|--can-rx)   shift; can_rx_interface="$1"
        if [[ "$can_rx_interface" != "can0" && "$can_rx_interface" != "can1" ]]; then
          echo "Receive interface must be can0 or can1"; exit 1; fi ;;
      -s|--size)     shift; can_frame_data_size="$1"
        if [[ "$can_frame_data_size" =~ $integer_regex ]]; then
          local ok=0
          for v in "${can_dlc_array[@]}"; do [[ "$v" == "$can_frame_data_size" ]] && ok=1; done
          [[ $ok -eq 1 ]] || { echo "Size must be valid DLC or 'i'"; exit 1; }
        else
          [[ "$can_frame_data_size" == "i" ]] || { echo "Size must be DLC or 'i'"; exit 1; }
        fi ;;
      -l|--length)   shift; time_gen="$1"
        [[ "$time_gen" =~ $integer_regex ]] || { echo "Length must be positive integer"; exit 1; } ;;
      -D|--payload)  shift; payload_data="$1"
        if ! [[ "$payload_data" =~ $hex_regex || "$payload_data" == "$payload_increment_mode" || "$payload_data" == "$payload_random_mode" ]]; then
          echo "Payload must be 'i', 'r', or HEX (e.g., DE42AD37)"; exit 1; fi ;;
      --out|--log)   shift; out_file="$1" ;;
      -h|--help)     usage; exit 0 ;;
      *) echo "$0: Invalid option $1"; usage; exit 1 ;;
    esac
    shift
  done

  # Requireds
  [[ "$tx_id" == "notset" ]] && { echo "tx_id required"; usage; exit 1; }
  [[ "$can_tx_interface" == "notset" ]] && { echo "tx_interface required"; usage; exit 1; }
  if [[ "$rx_id" == "notset" || "$can_rx_interface" == "notset" ]]; then
    echo "rx_id and rx_interface required"; usage; exit 1; fi
  [[ "$can_frame_data_size" == "notset" ]] && { echo "frame size required"; usage; exit 1; }
  [[ "$time_gen" == "notset" ]] && { echo "length required"; usage; exit 1; }
  [[ "$frame_gap_ms" == "notset" ]] && { echo "gap required"; usage; exit 1; }

  # Convert IDs to hex (uppercase) WITHOUT 0x for can-utils
  # my_canperf.sh validates decimal; we keep same UX but convert for tools
  printf -v tx_hex "%X" "$tx_id"
  printf -v rx_hex "%X" "$rx_id"

  echo "Transmit CAN id         : 0x${tx_hex} (${tx_id})"
  echo "Receive CAN id          : 0x${rx_hex} (${rx_id})"
  echo "CAN transmit interface  : ${can_tx_interface}"
  echo "CAN receive interface   : ${can_rx_interface}"
  echo "candump output          : ${out_file}"
}

setup_can() {
  # Bring interfaces up via GoldVIP service if needed
  ip a | grep -Eq ": ${can_tx_interface}:.*state UP" || service can restart "${can_tx_interface}"
  ip a | grep -Eq ": ${can_rx_interface}:.*state UP" || service can restart "${can_rx_interface}"
  sleep 1
}

run_capture() {
  # Correct filter mask based on RX ID width
  local id_mask
  if [[ $rx_id -le 2047 ]]; then
    id_mask="7FF"            # standard 11-bit exact match
  else
    id_mask="1FFFFFFF"       # extended 29-bit exact match
  fi

  # Start candump with delta time (latency.py expects '(delta)' prefix)
  rm -f "${out_file}"
  candump -td "${can_rx_interface},${rx_hex}:${id_mask}" > "${out_file}" &
  pid_candump=$!

  # Build cangen args like my_canperf.sh (no timeout; we'll sleep then kill)
  # -p 10: fixed payload pattern spacing (as in NXP script)
  # -b   : generate CAN FD bit-rate switch flag if supported (kept for parity)
  # -v -v: verbose (discarded to /dev/null below)
  # NOTE: cangen expects hex for -I (no 0x), so we pass ${tx_hex}
  cangen "${can_tx_interface}" -g "${frame_gap_ms}" -p 10 -b -I "${tx_hex}" \
         -L "${can_frame_data_size}" -D "${payload_data}" -v -v >/dev/null 2>&1 &
  pid_cangen=$!

  echo "Running for ${time_gen}s..."
  sleep "${time_gen}" || true

  # Stop TX then RX; ensure exit even if tools misbehave
  cleanup_and_exit 0
}

set_trap
check_input "$@"
setup_can
run_capture

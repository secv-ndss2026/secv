#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
#
# my_canperf_candump.sh — GoldVIP-friendly capture-only (candump -t d) runner
# - Mirrors my_canperf.sh options/validations so it runs on NXP GoldVIP as-is.
# - Starts candump with delta-time prefix to produce a latency.py-compatible file.
# - Starts cangen with the same semantics as my_canperf.sh (gap/size/payload/length).
# - DOES NOT compute any report; user runs:  python3 latency.py <candump.txt>
#
# Usage (example):
#   ./my_canperf_candump.sh -t can0 -r can1 -i 291 -o 291 -g 10 -s 8 -l 5 -D i --out /tmp/candump.txt
#
set -Ee

# Defaults (mirroring names from my_canperf.sh)
rx_id=notset
tx_id=notset
can_tx_interface=notset
can_rx_interface=notset
frame_gap_ms=notset
can_frame_data_size=notset
time_gen=notset

# Payload mode: same semantics (i = incremental, r = random, or HEX)
payload_random_mode="r"
payload_increment_mode="i"
payload_data="${payload_increment_mode}"

# Output candump path
out_file="/tmp/candump.txt"

# Jobs
pid_candump=0
pid_cangen=0

readonly integer_regex="^[0-9]+$"
readonly hex_regex="^[0-9A-Fa-f]+$"
readonly can_dlc_array=("1" "2" "3" "4" "5" "6" "7" "8" "12" "16" "20" "24" "32" "48" "64")

set_trap() {
  trap 'stop_cangen ; stop_candump ; exit 1' INT
  trap 'echo "An error occurred in $0 at line ${BASH_LINENO[0]}" ; stop_cangen ; stop_candump ; exit 1' ERR
}

usage() {
  cat <<USAGE
Usage: ./$(basename "$0") [options]
  -t | --can-tx <can i/f name>     CAN TX interface, e.g., can0 or can1
  -r | --can-rx <can i/f name>     CAN RX interface, e.g., can0 or can1
  -i | --tx-id <decimal>           Transmitted CAN message ID (0..2047)
  -o | --rx-id <decimal>           Received CAN message ID (0..2047)
  -g | --gap <ms>                  Frame gap in milliseconds
  -s | --size <bytes|i>            CAN(FD) frame size or 'i' for variable
  -l | --length <seconds>          Duration (seconds)
  -D | --payload <i|r|HEX>         Payload: i(increment), r(random), or HEX (e.g., DE42AD37)
  --out <path>                     candump output path (default: /tmp/candump.txt)
  -h | --help                      Help
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
        [[ "$tx_id" =~ $integer_regex ]] || { echo "CAN ID must be positive integer"; exit 1; }
        if [[ -z "$tx_id" || $((tx_id)) -lt 0 || $((tx_id)) -gt 2047 ]]; then
          echo "CAN ID must be between 0 and 2047"; exit 1; fi ;;
      -o|--rx-id)    shift; rx_id="$1"
        [[ "$rx_id" =~ $integer_regex ]] || { echo "CAN ID must be positive integer"; exit 1; }
        if [[ -z "$rx_id" || $((rx_id)) -lt 0 || $((rx_id)) -gt 2047 ]]; then
          echo "CAN ID must be between 0 and 2047"; exit 1; fi ;;
      -t|--can-tx)   shift; can_tx_interface="$1"
        if [[ "$can_tx_interface" != "can0" && "$can_tx_interface" != "can1" ]]; then
          echo "Transmit interface must be can0 or can1"; exit 1; fi ;;
      -r|--can-rx)   shift; can_rx_interface="$1"
        if [[ "$can_rx_interface" != "can0" && "$can_rx_interface" != "can1" ]]; then
          echo "Receive interface must be can0 or can1"; exit 1; fi ;;
      -s|--size)     shift; can_frame_data_size="$1"
        if [[ "$can_frame_data_size" =~ $integer_regex ]]; then
          if ! [[ " ${can_dlc_array[*]} " =~ ${can_frame_data_size} ]]; then
            echo "Size must be a valid CAN FD size or 'i'"; exit 1; fi
        else
          [[ "$can_frame_data_size" == "i" ]] || { echo "Size must be CAN FD size or 'i'"; exit 1; }
        fi ;;
      -l|--length)   shift; time_gen="$1"
        [[ "$time_gen" =~ $integer_regex ]] || { echo "Length must be positive integer"; exit 1; } ;;
      -D|--payload)  shift; payload_data="$1"
        if ! [[ "$payload_data" =~ $hex_regex || "$payload_data" == "$payload_increment_mode" || "$payload_data" == "$payload_random_mode" ]]; then
          echo "Payload must be 'i', 'r', or HEX (e.g., DE42AD37)"; exit 1; fi ;;
      --out)         shift; out_file="$1" ;;
      -h|--help)     usage; exit 0 ;;
      *) echo "$0: Invalid option $1"; usage; exit 1 ;;
    esac
    shift
  done

  # Requireds (same semantics as my_canperf.sh)
  if [[ "$tx_id" == "notset" ]]; then echo "tx_id required"; usage; exit 1; fi
  if [[ "$can_tx_interface" == "notset" ]]; then echo "tx_interface required"; usage; exit 1; fi
  if [[ "$rx_id" == "notset" || "$can_rx_interface" == "notset" ]]; then
    echo "rx_id and rx_interface required (this script always captures RX)"; usage; exit 1; fi
  if [[ "$can_frame_data_size" == "notset" ]]; then echo "frame size required"; usage; exit 1; fi
  if [[ "$time_gen" == "notset" ]]; then echo "length required"; usage; exit 1; fi
  if [[ "$frame_gap_ms" == "notset" ]]; then echo "gap required"; usage; exit 1; fi

  tx_id=$(printf 0x%x "${tx_id}")
  rx_id=$(printf 0x%x "${rx_id}")

  echo "Transmit CAN id         : ${tx_id}"
  echo "Receive CAN id          : ${rx_id}"
  echo "CAN transmit interface  : ${can_tx_interface}"
  echo "CAN receive interface   : ${can_rx_interface}"
  echo "candump output          : ${out_file}"
}

setup_can() {
  # Use GoldVIP 'service can' if iface is not already UP (same behavior).
  ip a | grep -Eq ": ${can_tx_interface}:.*state UP" || service can restart "${can_tx_interface}"
  ip a | grep -Eq ": ${can_rx_interface}:.*state UP" || service can restart "${can_rx_interface}"
  sleep 1
}

stop_cangen() {
  disown ${pid_cangen} 2>/dev/null || true
  kill ${pid_cangen} 2>/dev/null || true
  sleep 1
}

stop_candump() {
  disown ${pid_candump} 2>/dev/null || true
  kill ${pid_candump} 2>/dev/null || true
}

run_capture() {
  local id_filter=FFFFFFFF
  rm -f "${out_file}"

  # candump with delta-time for latency.py "(0.xxxxx)" prefix
  candump -t d "${can_rx_interface}","${rx_id}":"${id_filter}" > "${out_file}" &
  pid_candump=$!

  # Calculate frames count like original (ceil)
  local gen_frames_opt=""
  if [[ ${frame_gap_ms} -gt 0 ]]; then
    local gen_frames_count=$((time_gen * 1000 / frame_gap_ms + !! (time_gen * 1000 % frame_gap_ms)))
    gen_frames_opt="-n ${gen_frames_count}"
  fi

  # Start cangen; use timeout to guarantee exit
  timeout "${time_gen}" cangen "${can_tx_interface}" -g "${frame_gap_ms}" -p 10 -b -I "${tx_id}" \
      -L "${can_frame_data_size}" -D "${payload_data}" ${gen_frames_opt} -v -v >/dev/null &
  pid_cangen=$!

  echo "Running CAN generator for ${time_gen}s..."
  wait ${pid_cangen} || true
  stop_cangen
  stop_candump

  local lines
  lines=$(wc -l < "${out_file}" || echo 0)
  echo "[INFO] Captured ${lines} lines in ${out_file}"
  echo "[NEXT] Run: python3 latency.py ${out_file}"
}

set_trap
check_input "$@"
setup_can
run_capture

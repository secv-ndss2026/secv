#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
#
# my_canperf_candump_goldvip.sh — Based on NXP GoldVIP my_canperf.sh
# - Same options/validations/bring-up as original
# - Only captures candump in delta-time format for latency.py
# - No report / M7 load

set -Ee

# ====== original variables / defaults (kept) ======
rx_id=notset
tx_id=notset
can_tx_interface=notset
can_rx_interface=notset
frame_gap_ms=notset
can_frame_data_size=notset
time_gen=notset

pid_candump=0
pid_cangen=0

payload_random_mode="r"
payload_increment_mode="i"
payload_data="${payload_increment_mode}"

readonly integer_regex="^[0-9]+$"
readonly hex_regex="^[0-9A-Fa-f]+$"
readonly can_dlc_array=("1" "2" "3" "4" "5" "6" "7" "8" "12" "16" "20" "24" "32" "48" "64")

# original semantics: --log is "use existing log (overrides cangen)"
user_log_file=""

# NEW: candump output file path (delta-time)
out_file="/tmp/candump.txt"

set_trap() {
  trap 'stop_cangen ; stop_candump ; exit 1' INT
  trap 'echo "An error occurred in $0 at line ${BASH_LINENO[0]}" ; stop_cangen ; stop_candump ; exit 1' ERR
}

usage() {
  echo -e "Usage: ./$(basename "$0") [options]
OPTIONS:
  -t | --can-tx <can0|can1>      CAN transmit interface
  -r | --can-rx <can0|can1>      CAN receive interface
  -i | --tx-id <decimal>         Transmitted CAN message ID (0..2047)
  -o | --rx-id <decimal>         Received CAN message ID (0..2047)
  -g | --gap <ms>                Frame gap in milliseconds
  -s | --size <bytes|i>          CAN(FD) size or 'i'
  -l | --length <seconds>        Session length (seconds)
  -D | --payload <i|r|HEX>       Payload mode or HEX
  --log <path_to_log_file>       Use existing TX log (overrides cangen)  [ORIGINAL MEANING]
  --out <path>                   candump delta-time output (default: /tmp/candump.txt)
  -h | --help                    help

Then run:
  python3 latency.py <candump_output.txt>
"
}

check_input() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -g|--gap)       shift; frame_gap_ms=${1}
        [[ "${frame_gap_ms}" =~ ${integer_regex} ]] || { echo "Frame gap must be a positive integer"; exit 1; } ;;
      -i|--tx-id)     shift; tx_id=${1}
        [[ "${tx_id}" =~ ${integer_regex} ]] || { echo "CAN ID must be a positive integer"; exit 1; }
        if [[ -z "${tx_id}" || $((tx_id)) -lt 0 || $((tx_id)) -gt 2047 ]]; then
          echo "CAN ID must be 0..2047"; exit 1; fi ;;
      -o|--rx-id)     shift; rx_id=${1}
        [[ "${rx_id}" =~ ${integer_regex} ]] || { echo "CAN ID must be a positive integer"; exit 1; }
        if [[ -z "${rx_id}" || $((rx_id)) -lt 0 || $((rx_id)) -gt 2047 ]]; then
          echo "CAN ID must be 0..2047"; exit 1; fi ;;
      -t|--can-tx)    shift; can_tx_interface=${1}
        if [[ "${can_tx_interface}" != "can0" && "${can_tx_interface}" != "can1" ]]; then
          echo "Transmit interface must be can0 or can1"; exit 1; fi ;;
      -r|--can-rx)    shift; can_rx_interface=${1}
        if [[ "${can_rx_interface}" != "can0" && "${can_rx_interface}" != "can1" ]]; then
          echo "Receive interface must be can0 or can1"; exit 1; fi ;;
      -s|--size)      shift; can_frame_data_size=${1}
        if [[ "${can_frame_data_size}" =~ ${integer_regex} ]]; then
          if ! [[ " ${can_dlc_array[*]} " =~ ${can_frame_data_size} ]]; then
            echo "Frame size must be a valid CAN FD size or 'i'"; exit 1; fi
        else
          [[ "${can_frame_data_size}" == "i" ]] || { echo "Frame size must be valid or 'i'"; exit 1; }
        fi ;;
      -l|--length)    shift; time_gen=${1}
        [[ "${time_gen}" =~ ${integer_regex} ]] || { echo "Length must be a positive integer"; exit 1; } ;;
      -D|--payload)   shift; payload_data=${1}
        if ! [[ "${payload_data}" =~ ${hex_regex} || "${payload_data}" == "${payload_increment_mode}" || "${payload_data}" == "${payload_random_mode}" ]]; then
          echo "Payload must be 'i'|'r' or HEX"; exit 1; fi ;;
      --log)          shift; user_log_file=${1}
        if [[ ! -f "${user_log_file}" ]]; then echo "Given log file does not exist: ${user_log_file}"; exit 1; fi ;;
      --out)          shift; out_file=${1} ;;
      -h|--help) usage; exit 0 ;;
      *) echo "$0: Invalid option $1"; usage; exit 1 ;;
    esac
    shift
  done

  # Requireds (same as original)
  if [[ -z "$user_log_file" && "$tx_id" == "notset" ]]; then echo "tx_id required"; usage; exit 1; fi
  if [[ "${can_tx_interface}" == "notset" ]]; then echo "tx_interface required"; usage; exit 1; fi

  # RX required for capture
  if [[ "${rx_id}" == "notset" || "${can_rx_interface}" == "notset" ]]; then
    echo "rx_id and rx_interface required"; usage; exit 1
  fi

  if [[ -z "$user_log_file" && "$can_frame_data_size" == "notset" ]]; then echo "frame size required"; usage; exit 1; fi
  if [[ -z "$user_log_file" && "$time_gen" == "notset" ]]; then echo "length required"; usage; exit 1; fi
  if [[ -z "$user_log_file" && "$frame_gap_ms" == "notset" ]]; then echo "gap required"; usage; exit 1; fi

  # hex formatting like original
  if [[ "$tx_id" != "notset" ]]; then tx_id=$(printf 0x%x "${tx_id}"); fi
  rx_id=$(printf 0x%x "${rx_id}")

  echo "Transmit CAN id         : ${tx_id}"
  echo "Receive CAN id          : ${rx_id}"
  echo "CAN transmit interface  : ${can_tx_interface}"
  echo "CAN receive interface   : ${can_rx_interface}"
  echo "candump output          : ${out_file}"
}

setup_can() {
  ip a | grep -Eq ": ${can_tx_interface}:.*state UP" || service can restart "${can_tx_interface}"
  ip a | grep -Eq ": ${can_rx_interface}:.*state UP" || service can restart "${can_rx_interface}"
  sleep 1
}

stop_cangen()  { disown ${pid_cangen}  2>/dev/null || true; kill ${pid_cangen}  2>/dev/null || true; sleep 1; }
stop_candump() { disown ${pid_candump} 2>/dev/null || true; kill ${pid_candump} 2>/dev/null || true; }

run_capture_only() {
  local id_filter=FFFFFFFF
  rm -f "${out_file}"

  # RX: delta-time for latency.py (changed from original -S)
  candump -t d "${can_rx_interface}","${rx_id}":"${id_filter}" > "${out_file}" &
  pid_candump=$!

  # TX frames count & options (same as original)
  local gen_frames_opt=""
  if [[ ${frame_gap_ms} -gt 0 ]]; then
    local gen_frames_count=$((time_gen * 1000 / frame_gap_ms + !! (time_gen * 1000 % frame_gap_ms)))
    gen_frames_opt="-n ${gen_frames_count}"
  fi

  if [[ -n "$user_log_file" ]]; then
    # When --log is given (original behavior): replay as TX
    local tx_log="/tmp/cangen.log"
    cp "$user_log_file" "$tx_log"
    sed -i -E 's/^(\([0-9]+\.[0-9]+\)) /\1 can0 /' "$tx_log"
    canplayer -I "$tx_log" &
    pid_cangen=$!
  else
    timeout "${time_gen}" cangen "${can_tx_interface}" -g "${frame_gap_ms}" -p 10 -b -I "${tx_id}" \
            -L "${can_frame_data_size}" -D "${payload_data}" "${gen_frames_opt}" -v -v >/dev/null &
    pid_cangen=$!
  fi

  echo "Running CAN generator..."
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
run_capture_only

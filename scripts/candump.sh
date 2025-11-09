#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# candump.sh — Minimal CAN capture based on my_canperf.sh (latency.py ready)

set -Ee

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

candump_file="/tmp/candump.txt"

usage() {
  echo "Usage: ./candump.sh -t canX -r canY -i <dec> -o <dec> -g <ms> -s <DLC|i> -l <sec> -D <i|r|HEX> --log <path>"
}

check_input() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -g|--gap)       shift; frame_gap_ms=${1}
        [[ "${frame_gap_ms}" =~ ${integer_regex} ]] || { echo "Frame gap must be integer"; exit 1; } ;;
      -i|--tx-id)     shift; tx_id=${1}
        [[ "${tx_id}" =~ ${integer_regex} ]] || { echo "TX CAN ID integer"; exit 1; }
        if [[ -z "${tx_id}" || $((tx_id)) -lt 0 || $((tx_id)) -gt 2047 ]]; then
          echo "TX CAN ID 0..2047"; exit 1; fi ;;
      -o|--rx-id)     shift; rx_id=${1}
        [[ "${rx_id}" =~ ${integer_regex} ]] || { echo "RX CAN ID integer"; exit 1; }
        if [[ -z "${rx_id}" || $((rx_id)) -lt 0 || $((rx_id)) -gt 2047 ]]; then
          echo "RX CAN ID 0..2047"; exit 1; fi ;;
      -t|--can-tx)    shift; can_tx_interface=${1}
        if [[ "${can_tx_interface}" != "can0" && "${can_tx_interface}" != "can1" ]]; then
          echo "TX interface incorrect"; exit 1; fi ;;
      -r|--can-rx)    shift; can_rx_interface=${1}
        if [[ "${can_rx_interface}" != "can0" && "${can_rx_interface}" != "can1" ]]; then
          echo "RX interface incorrect"; exit 1; fi ;;
      -s|--size)      shift; can_frame_data_size=${1}
        if [[ "${can_frame_data_size}" =~ ${integer_regex} ]] && ! [[ " ${can_dlc_array[*]} " =~ ${can_frame_data_size} ]]; then
          echo "Invalid DLC"; exit 1;
        elif [[ ! "${can_frame_data_size}" =~ ${integer_regex} && "${can_frame_data_size}" != "i" ]]; then
          echo "Invalid DLC"; exit 1;
        fi ;;
      -l|--length)    shift; time_gen=${1}
        [[ "${time_gen}" =~ ${integer_regex} ]] || { echo "Length integer"; exit 1; } ;;
      -D|--payload)   shift; payload_data=${1}
        if ! [[ "${payload_data}" =~ ${hex_regex} || "${payload_data}" == "${payload_increment_mode}" ||  "${payload_data}" == "${payload_random_mode}" ]]; then
          echo "Payload i|r|HEX"; exit 1; fi ;;
      --log)          shift; candump_file=${1} ;;
      -h|--help) usage; exit 0 ;;
      *) echo "$0: Invalid option $1"; usage; exit 1 ;;
    esac
    shift
  done

  [[ "$tx_id" == "notset" ]] && { echo "tx_id required"; usage; exit 1; }
  [[ "${can_tx_interface}" == "notset" ]] && { echo "tx interface required"; usage; exit 1; }
  if [[ "${rx_id}" == "notset" || "${can_rx_interface}" == "notset" ]]; then
    echo "rx_id and rx_interface required"; usage; exit 1; fi
  [[ "$can_frame_data_size" == "notset" ]] && { echo "frame size required"; usage; exit 1; }
  [[ "$time_gen" == "notset" ]] && { echo "length required"; usage; exit 1; }
  [[ "$frame_gap_ms" == "notset" ]] && { echo "gap required"; usage; exit 1; }

  tx_hex=$(printf 0x%x "${tx_id}")
  rx_hex=$(printf 0x%x "${rx_id}")

  echo "Transmit CAN id         : ${tx_hex}"
  echo "Receive CAN id          : ${rx_hex}"
  echo "CAN transmit interface  : ${can_tx_interface}"
  echo "CAN receive interface   : ${can_rx_interface}"
  echo "candump output          : ${candump_file}"
}

setup_can() {
  ip a | grep -Eq ": ${can_tx_interface}:.*state UP" || service can restart "${can_tx_interface}"
  ip a | grep -Eq ": ${can_rx_interface}:.*state UP" || service can restart "${can_rx_interface}"
  sleep 1
}

stop_cangen()  { disown ${pid_cangen}  2>/dev/null || true; kill ${pid_cangen}  2>/dev/null || true; sleep 1; }
stop_candump() { disown ${pid_candump} 2>/dev/null || true; kill ${pid_candump} 2>/dev/null || true; }

run_capture_min() {
  local id_filter=7FF
  rm -f "${candump_file}"

  candump -t d "${can_rx_interface},${rx_hex}:${id_filter}" > "${candump_file}" &
  pid_candump=$!

  local gen_frames_opt=""
  if [[ ${frame_gap_ms} -gt 0 ]]; then
    local gen_frames_count=$((time_gen * 1000 / frame_gap_ms + !! (time_gen * 1000 % frame_gap_ms)))
    gen_frames_opt="-n ${gen_frames_count}"
  fi

  timeout "${time_gen}" cangen "${can_tx_interface}" -g "${frame_gap_ms}" -p 10 -b -I "${tx_hex}" \
        -L "${can_frame_data_size}" -D "${payload_data}" ${gen_frames_opt} -v -v >/dev/null &
  pid_cangen=$!

  echo "Running CAN generator..."
  wait ${pid_cangen} || true
  stop_cangen
  stop_candump

  local lines
  lines=$(wc -l < "${candump_file}" || echo 0)
  echo "[INFO] Captured ${lines} lines in ${candump_file}"
  echo "[NEXT] Run: python3 latency.py ${candump_file}"
}

check_input "$@"
setup_can
run_capture_min

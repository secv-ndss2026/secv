#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# candump.sh — minimal capture, mirroring my_canperf.sh behavior (no extras)
# Usage:
#   ./candump.sh -t can0 -r can1 -g 10 -s 8 --log candump.txt
#
set -Ee

# Defaults (align with typical my_canperf.sh expectations)
can_tx=notset
can_rx=notset
gap_ms=notset
dlc=notset
length=5          # default length if -l not given
tx_id=291         # 0x123
rx_id=291         # 0x123
payload=i         # i|r|HEX
out_file="/tmp/candump.txt"

pid_dump=0
pid_gen=0
integer='^[0-9]+$'
hex='^[0-9A-Fa-f]+$'
valid_dlc=("1" "2" "3" "4" "5" "6" "7" "8" "12" "16" "20" "24" "32" "48" "64")

usage() {
  cat <<USAGE
Usage: ./candump.sh -t canX -r canY -g <ms> -s <DLC> [options]
  -t|--can-tx   can0|can1
  -r|--can-rx   can0|can1
  -g|--gap      gap ms
  -s|--size     DLC (1..8,12,16,20,24,32,48,64)
  -l|--length   seconds (default 5)
  -i|--tx-id    decimal ID (0..2047, default 291=0x123)
  -o|--rx-id    decimal ID (0..2047, default 291=0x123)
  -D|--payload  i|r|HEX (default i)
  --log         candump output path (default /tmp/candump.txt)
USAGE
}

trap 'kill $pid_gen 2>/dev/null || true; kill $pid_dump 2>/dev/null || true; exit 1' INT ERR

# Parse args (identical names, no extra options)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--can-tx) shift; can_tx="$1" ;;
    -r|--can-rx) shift; can_rx="$1" ;;
    -g|--gap)    shift; gap_ms="$1" ;;
    -s|--size)   shift; dlc="$1" ;;
    -l|--length) shift; length="$1" ;;
    -i|--tx-id)  shift; tx_id="$1" ;;
    -o|--rx-id)  shift; rx_id="$1" ;;
    -D|--payload) shift; payload="$1" ;;
    --log)       shift; out_file="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Invalid option: $1"; usage; exit 1 ;;
  esac
  shift || true
done

# Validations (same spirit as my_canperf.sh)
[[ "$can_tx" == "notset" ]] && { echo "tx interface required"; usage; exit 1; }
[[ "$can_rx" == "notset" ]] && { echo "rx interface required"; usage; exit 1; }
[[ "$gap_ms" =~ $integer ]] || { echo "gap must be integer ms"; exit 1; }
[[ "$length" =~ $integer ]] || { echo "length must be integer sec"; exit 1; }
if [[ "$dlc" =~ $integer ]]; then
  ok=0; for v in "${valid_dlc[@]}"; do [[ "$v" == "$dlc" ]] && ok=1; done
  [[ $ok -eq 1 ]] || { echo "invalid DLC: $dlc"; exit 1; }
else
  [[ "$dlc" == "i" ]] || { echo "DLC must be valid size or 'i'"; exit 1; }
fi
[[ "$tx_id" =~ $integer && $tx_id -ge 0 && $tx_id -le 2047 ]] || { echo "tx-id 0..2047"; exit 1; }
[[ "$rx_id" =~ $integer && $rx_id -ge 0 && $rx_id -le 2047 ]] || { echo "rx-id 0..2047"; exit 1; }
if ! [[ "$payload" == "i" || "$payload" == "r" || "$payload" =~ $hex ]]; then
  echo "payload must be i|r|HEX"; exit 1
fi

# Bring interfaces up via GoldVIP service
ip a | grep -Eq ": ${can_tx}:.*state UP" || service can restart "${can_tx}"
ip a | grep -Eq ": ${can_rx}:.*state UP" || service can restart "${can_rx}"
sleep 1

# Exact-match filter for 11-bit ID
printf -v RX_HEX "%X" "$rx_id"
mask="7FF"
: > "$out_file"

# Start candump (delta time → latency.py compatible)
candump -t d "${can_rx},${RX_HEX}:${mask}" > "$out_file" &
pid_dump=$!

# Compute number of frames so cangen ends naturally
frames=$(( length * 1000 / gap_ms ))
if (( (length * 1000) % gap_ms != 0 )); then frames=$((frames+1)); fi
(( frames < 1 )) && frames=1

# TX_HEX (no 0x) for can-utils
printf -v TX_HEX "%X" "$tx_id"

# Generate traffic (same flags style)
cangen "$can_tx" -g "$gap_ms" -p 10 -b -I "$TX_HEX" -L "$dlc" -D "$payload" -n "$frames" -v -v >/dev/null 2>&1 &
pid_gen=$!

# Wait and cleanup
wait "$pid_gen" 2>/dev/null || true
sleep 0.2
kill "$pid_dump" 2>/dev/null || true
wait "$pid_dump" 2>/dev/null || true

lines=$(wc -l < "$out_file" 2>/dev/null || echo 0)
echo "[INFO] Captured ${lines} lines in ${out_file}"
echo "[NEXT] python3 latency.py ${out_file}"

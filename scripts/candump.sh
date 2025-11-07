#!/usr/bin/env bash
# my_canperf_vcan.sh — TX(cangen) + RX(candump) in one terminal
# Options mirror my_canperf.sh for familiarity.
#
# Example:
#   ./my_canperf_vcan.sh -t vcan0 -r vcan0 -i 0x123 -o 0x123 -g 10 -s 8 -l 5 --log candump.txt
#
set -Eeuo pipefail

# Defaults
can_tx=""
can_rx=""
tx_id=""
rx_id=""
frame_gap_ms=5
dlc=8
length_sec=10
log_file="candump.txt"
payload=""   # optional hex payload string (no spaces)
use_swapped=0

integer_regex='^[0-9]+$'
hex0x_regex='^0x[0-9A-Fa-f]+$'
hex_regex='^[0-9A-Fa-f]+$'

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]
  -t | --can-tx <if>       TX interface (e.g., can0, vcan0)
  -r | --can-rx <if>       RX interface (e.g., can0, vcan0)
  -i | --tx-id  <id>       TX CAN ID (decimal or 0xHEX)
  -o | --rx-id  <id>       RX filter CAN ID (decimal or 0xHEX)
  -g | --gap    <ms>       Inter-frame gap for TX (default: 10)
  -s | --size   <0..8>     DLC / payload size (default: 8)
  -l | --length <sec>      Duration to run (default: 10)
  -D | --payload <HEX>     Fixed payload bytes (continuous HEX, e.g., AABBCCDDEEFF0011)
  -S                       candump with swapped payload print (matches 'candump -S'; optional)
  --log <path>             Output file for candump (default: ./candump.txt)
  -h | --help              Show this help

After capture, run:
  python3 latency.py <candump_output.txt>
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--can-tx) shift; can_tx="${1:-}";;
    -r|--can-rx) shift; can_rx="${1:-}";;
    -i|--tx-id)  shift; tx_id="${1:-}";;
    -o|--rx-id)  shift; rx_id="${1:-}";;
    -g|--gap)    shift; frame_gap_ms="${1:-}";;
    -s|--size)   shift; dlc="${1:-}";;
    -l|--length) shift; length_sec="${1:-}";;
    -D|--payload) shift; payload="${1:-}";;
    --log)       shift; log_file="${1:-}";;
    -S) use_swapped=1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
  shift || true
done

[[ -z "$can_tx" || -z "$can_rx" ]] && die "Both --can-tx and --can-rx are required"
[[ -n "$frame_gap_ms" && "$frame_gap_ms" =~ ^[0-9]+$ ]] || die "Frame gap must be a positive integer"
[[ -n "$length_sec" && "$length_sec" =~ ^[0-9]+$ ]] || die "Length must be a positive integer"
[[ -n "$dlc" && "$dlc" =~ ^[0-9]+$ && $dlc -ge 0 && $dlc -le 8 ]] || die "Size/DLC must be 0..8"

to_hex() {
  local s="$1"
  if [[ "$s" =~ $hex0x_regex ]]; then
    s="${s#0x}"
  elif [[ "$s" =~ $integer_regex ]]; then
    printf "%x" "$s"
    return
  elif [[ "$s" =~ $hex_regex ]]; then
    :
  else
    die "ID must be decimal or 0xHEX"
  fi
  echo "$s"
}
[[ -z "$tx_id" ]] && die "--tx-id is required"
[[ -z "$rx_id" ]] && die "--rx-id is required"
tx_hex="$(to_hex "$tx_id" | tr '[:lower:]' '[:upper:]')"
rx_hex="$(to_hex "$rx_id" | tr '[:lower:]' '[:upper:]')"

if ! ip -br link show "$can_tx" 2>/dev/null | grep -q "UP"; then
  sudo ip link set "$can_tx" up || true
fi
if ! ip -br link show "$can_rx" 2>/dev/null | grep -q "UP"; then
  sudo ip link set "$can_rx" up || true
fi

dump_mask="7FF"
if [[ ${#rx_hex} -gt 3 ]]; then
  dump_mask="1FFFFFFF"
fi

: > "$log_file"

echo "[INFO] TX=${can_tx}  RX=${can_rx}  TX_ID=0x${tx_hex}  RX_ID=0x${rx_hex}  GAP=${frame_gap_ms}ms  DLC=${dlc}  DUR=${length_sec}s"
echo "[INFO] Writing candump to: ${log_file}"

# Cleanup
pids=()
cleanup() {
  for p in "${pids[@]:-}"; do
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# Start candump (-t d, optional -S)
if [[ "$use_swapped" -eq 1 ]]; then
  candump -t d -S "${can_rx},${rx_hex}:${dump_mask}" > "$log_file" &
else
  candump -t d    "${can_rx},${rx_hex}:${dump_mask}" > "$log_file" &
fi
pids+=("$!")

# Build cangen payload args
cangen_args=("$can_tx" -I "$tx_hex" -L "$dlc" -g "$frame_gap_ms")
if [[ -n "$payload" ]]; then
  # cangen accepts -D for fixed payload (continuous HEX string)
  cangen_args+=(-D "$payload")
fi

cangen "${cangen_args[@]}" &
pids+=("$!")

sleep "$length_sec" || true

lines=$(wc -l < "$log_file" || echo 0)
echo "[INFO] Captured ${lines} lines in ${log_file}"

#!/bin/sh
# candump.sh — ultra-minimal, my_canperf.sh-style capture for latency.py
# Usage:
#   ./candump.sh -t can0 -r can1 -g 10 -s 8 --log candump.txt [-l 5] [-i 291] [-o 291] [-D i|r|HEX]

# ---- defaults ----
can_tx=
can_rx=
gap_ms=
dlc=
length=5
tx_id=291   # 0x123
rx_id=291   # 0x123
payload=i
out_file="/tmp/candump.txt"

integer='^[0-9][0-9]*$'
hex='^[0-9A-Fa-f]+$'
valid_dlc="1 2 3 4 5 6 7 8 12 16 20 24 32 48 64"

usage() {
  echo "Usage: $0 -t canX -r canY -g <ms> -s <DLC> [options]
  -t|--can-tx   can0|can1
  -r|--can-rx   can0|can1
  -g|--gap      gap ms
  -s|--size     DLC (1..8,12,16,20,24,32,48,64)
  -l|--length   seconds (default 5)
  -i|--tx-id    0..2047 (default 291)
  -o|--rx-id    0..2047 (default 291)
  -D|--payload  i|r|HEX (default i)
  --log         candump output path (default /tmp/candump.txt)"
}

# ---- parse ----
while [ $# -gt 0 ]; do
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
  shift
done

# ---- validate ----
[ -n "$can_tx" ] || { echo "tx interface required"; usage; exit 1; }
[ -n "$can_rx" ] || { echo "rx interface required"; usage; exit 1; }

echo "$gap_ms" | grep -Eq "$integer" || { echo "gap must be integer ms"; exit 1; }
echo "$length" | grep -Eq "$integer" || { echo "length must be integer sec"; exit 1; }

ok=0; for v in $valid_dlc; do [ "$v" = "$dlc" ] && ok=1; done
[ $ok -eq 1 ] || [ "$dlc" = "i" ] || { echo "invalid DLC: $dlc"; exit 1; }

echo "$tx_id" | grep -Eq "$integer" && [ "$tx_id" -ge 0 ] && [ "$tx_id" -le 2047 ] || { echo "tx-id 0..2047"; exit 1; }
echo "$rx_id" | grep -Eq "$integer" && [ "$rx_id" -ge 0 ] && [ "$rx_id" -le 2047 ] || { echo "rx-id 0..2047"; exit 1; }

case "$payload" in
  i|r) ;;
  *) echo "$payload" | grep -Eq "$hex" || { echo "payload must be i|r|HEX"; exit 1; } ;;
esac

# ---- bring up (GoldVIP style) ----
ip a | grep -Eq ": ${can_tx}:.*state UP" || service can restart "${can_tx}"
ip a | grep -Eq ": ${can_rx}:.*state UP" || service can restart "${can_rx}"
sleep 1

# ---- candump filter (exact SFF) ----
RX_HEX=$(printf "%X" "$rx_id")
mask="7FF"
: > "$out_file"

# Start candump in background (delta-time). Keep its PID.
candump -t d "${can_rx},${RX_HEX}:${mask}" > "$out_file" &
pid_dump=$!

# Compute frames so cangen finishes by itself
frames=$(( length * 1000 / gap_ms ))
[ $(( (length * 1000) % gap_ms )) -ne 0 ] && frames=$((frames+1))
[ $frames -lt 1 ] && frames=1

TX_HEX=$(printf "%X" "$tx_id")

# ---- Run cangen in FOREGROUND (no background, no redirection) ----
# If cangen errors, you'll see it on the terminal.
# Flags mirror my_canperf.sh style.
cangen "$can_tx" -g "$gap_ms" -p 10 -b -I "$TX_HEX" -L "$dlc" -D "$payload" -n "$frames"

# After cangen exits naturally, stop candump and summarize
kill "$pid_dump" 2>/dev/null || true
wait "$pid_dump" 2>/dev/null || true

lines=$(wc -l < "$out_file" 2>/dev/null || echo 0)
echo "[INFO] Captured ${lines} lines in ${out_file}"
echo "[NEXT] python3 latency.py ${out_file}"

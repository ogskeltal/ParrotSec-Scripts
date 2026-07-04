#!/usr/bin/env bash
#
# vuln-map.sh
#
# Map discovered services to candidate exploits. Given nmap XML or a ports.tsv
# from nmap-parse.sh, it queries searchsploit for each service/version and, if
# cve-poc.sh data is present, notes matching CVE PoCs. Output is a per-host list
# of leads to chase, not a confirmation of exploitability.
#
# Usage:
#   ./vuln-map.sh scan.xml
#   ./vuln-map.sh parsed/ports.tsv --out ./vulnmap
#   nmap -sV -oX - target | ./vuln-map.sh -
#
set -uo pipefail

OUT=""
die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -)         INPUT="-" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$INPUT" ] || die "Only one input."; INPUT="$1" ;;
  esac
  shift
done
[ -n "$INPUT" ] || { echo "No input (nmap XML or ports.tsv, - for stdin)." >&2; usage 2; }
have searchsploit || die "searchsploit not found (apt install exploitdb)."

SRC=$(mktemp)
if [ "$INPUT" = "-" ]; then cat > "$SRC"; else [ -f "$INPUT" ] || die "File not found: $INPUT"; cat "$INPUT" > "$SRC"; fi

report=""
[ -n "$OUT" ] && { mkdir -p "$OUT"; report="$OUT/vuln-map.txt"; }
emit() { if [ -n "$report" ]; then tee -a "$report"; else cat; fi; }

# --- nmap XML: let searchsploit do the matching directly ------------------
if grep -q '<nmaprun' "$SRC"; then
  echo ">> Detected nmap XML; running searchsploit --nmap..." | emit
  searchsploit --nmap "$SRC" 2>/dev/null | emit
  rm -f "$SRC"
  [ -n "$report" ] && echo ">> Report: $report"
  exit 0
fi

# --- ports.tsv from nmap-parse.sh -----------------------------------------
echo ">> Reading ports.tsv (HOST NAME PORT PROTO SERVICE VERSION)..." | emit
# Skip a header line if present.
seen_query=""
while IFS=$'\t' read -r host name port proto service version; do
  [ "$host" = "HOST" ] && continue
  [ -n "$service" ] || continue
  # Build a query from service + product/version, trimming placeholders.
  q=$(printf '%s %s' "$service" "$version" | sed 's/-\{1,\}//g; s/  */ /g; s/^ //; s/ $//')
  [ -n "$q" ] || q="$service"
  case "|$seen_query|" in *"|$q|"*) continue ;; esac
  seen_query="$seen_query|$q"

  {
    echo
    echo "==== ${host}:${port}/${proto}  ($service ${version:-})"
    res=$(searchsploit --color=never "$q" 2>/dev/null | grep -vE 'Exploits: No Result|Shellcode' | sed '/^-\{5,\}/d; /Exploit Title/d; /^$/d')
    if [ -n "$res" ]; then echo "$res"; else echo "   (no searchsploit hits for '$q')"; fi
  } | emit
done < "$SRC"
rm -f "$SRC"

echo | emit
echo ">> Leads only; verify versions and read exploits before running." | emit
[ -n "$report" ] && echo ">> Report: $report"

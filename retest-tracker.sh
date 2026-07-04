#!/usr/bin/env bash
#
# retest-tracker.sh
#
# Track findings across retests in a small CSV: id, title, severity, host,
# status, and last-updated. Add findings, flip their status on a retest, list by
# status, and emit a Markdown table for report-gen.sh.
#
# Usage:
#   ./retest-tracker.sh add --id F1 --title "SQLi in login" --severity High --host 10.0.0.5
#   ./retest-tracker.sh set F1 fixed
#   ./retest-tracker.sh list
#   ./retest-tracker.sh list --status open
#   ./retest-tracker.sh report            # Markdown table to stdout
#
# Status values: open, fixed, needs-retest, accepted-risk. File defaults to
# $FINDINGS_CSV, then ./report/findings.csv.
#
set -uo pipefail

FILE=""
ID=""; TITLE=""; SEV=""; HOST=""; STATUS_FILTER=""

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
ACTION=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --file)     shift; [ $# -gt 0 ] || die "--file needs a path"; FILE="$1" ;;
    --file=*)   FILE="${1#*=}" ;;
    --id)       shift; ID="$1" ;;
    --title)    shift; TITLE="$1" ;;
    --severity) shift; SEV="$1" ;;
    --host)     shift; HOST="$1" ;;
    --status)   shift; STATUS_FILTER="$1" ;;
    add|set|list|report)
      [ -z "$ACTION" ] || die "One action at a time."; ACTION="$1" ;;
    *)          POS+=("$1") ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "No action (add|set|list|report)." >&2; usage 2; }

if [ -z "$FILE" ]; then
  if [ -n "${FINDINGS_CSV:-}" ]; then FILE="$FINDINGS_CSV"; else FILE="./report/findings.csv"; fi
fi
HEADER="id,title,severity,host,status,updated"
ensure() { mkdir -p "$(dirname "$FILE")" 2>/dev/null || true; [ -f "$FILE" ] || printf '%s\n' "$HEADER" > "$FILE"; }
clean() { printf '%s' "$1" | tr ',\n' '; '; }   # keep CSV single-field

case "$ACTION" in
  add)
    [ -n "$ID" ] && [ -n "$TITLE" ] || die "add needs --id and --title."
    ensure
    grep -q "^$(clean "$ID")," "$FILE" && die "id '$ID' already exists (use 'set' to update)."
    printf '%s,%s,%s,%s,%s,%s\n' \
      "$(clean "$ID")" "$(clean "$TITLE")" "$(clean "${SEV:-Unknown}")" \
      "$(clean "$HOST")" "open" "$(date +%Y-%m-%d)" >> "$FILE"
    echo ">> Added $ID [open] -> $FILE"
    ;;
  set)
    [ "${#POS[@]}" -ge 2 ] || die "usage: set <id> <status>"
    ensure
    tid="${POS[0]}"; tstatus="${POS[1]}"
    case "$tstatus" in open|fixed|needs-retest|accepted-risk) ;; *) die "status must be open|fixed|needs-retest|accepted-risk" ;; esac
    grep -q "^$(clean "$tid")," "$FILE" || die "id '$tid' not found."
    today=$(date +%Y-%m-%d)
    awk -F, -v id="$tid" -v st="$tstatus" -v d="$today" 'BEGIN{OFS=","}
      NR==1{print; next}
      $1==id{$5=st; $6=d}
      {print}' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    echo ">> $tid -> $tstatus"
    ;;
  list)
    [ -f "$FILE" ] || die "No findings file at $FILE yet."
    if [ -n "$STATUS_FILTER" ]; then
      { head -n1 "$FILE"; awk -F, -v s="$STATUS_FILTER" 'NR>1 && $5==s' "$FILE"; }
    else cat "$FILE"; fi | { command -v column >/dev/null 2>&1 && column -t -s, || cat; }
    ;;
  report)
    [ -f "$FILE" ] || die "No findings file at $FILE yet."
    echo "| ID | Severity | Title | Host | Status | Updated |"
    echo "| -- | -------- | ----- | ---- | ------ | ------- |"
    awk -F, 'NR>1{printf "| %s | %s | %s | %s | %s | %s |\n",$1,$3,$2,$4,$5,$6}' "$FILE"
    ;;
esac

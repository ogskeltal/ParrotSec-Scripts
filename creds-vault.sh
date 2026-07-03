#!/usr/bin/env bash
#
# creds-vault.sh
#
# Append-only credential log for an engagement. Records host, service, user,
# secret, and source as tab-separated rows, and gives you list/search/count over
# them. Not encrypted; it's a structured scratchpad, so keep it in your
# engagement directory and shred it when you're done (panic-wipe.sh --loot).
#
# Usage:
#   ./creds-vault.sh add --host 10.0.0.5 --service smb --user admin --secret 'P@ss' --source secretsdump
#   ./creds-vault.sh list
#   ./creds-vault.sh search admin
#   ./creds-vault.sh count
#   ./creds-vault.sh --file ~/eng/acme/creds/vault.tsv list
#
# The vault file defaults to $CREDS_VAULT, then ./creds/vault.tsv.
#
set -uo pipefail

FILE=""
HOST="" SERVICE="" USER="" SECRET="" SOURCE="" NOTE=""

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
ACTION=""
TERM=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --file)     shift; [ $# -gt 0 ] || die "--file needs a path"; FILE="$1" ;;
    --file=*)   FILE="${1#*=}" ;;
    --host)     shift; HOST="$1" ;;
    --service)  shift; SERVICE="$1" ;;
    --user)     shift; USER="$1" ;;
    --secret)   shift; SECRET="$1" ;;
    --source)   shift; SOURCE="$1" ;;
    --note)     shift; NOTE="$1" ;;
    add|list|search|count)
      [ -z "$ACTION" ] || die "One action at a time."; ACTION="$1" ;;
    *)
      if [ "$ACTION" = "search" ] && [ -z "$TERM" ]; then TERM="$1";
      else die "Unexpected argument: $1"; fi ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "No action given (add|list|search|count)." >&2; usage 2; }

# --- resolve vault file ---------------------------------------------------
if [ -z "$FILE" ]; then
  if [ -n "${CREDS_VAULT:-}" ]; then FILE="$CREDS_VAULT"; else FILE="./creds/vault.tsv"; fi
fi

HEADER=$'ts\thost\tservice\tuser\tsecret\tsource\tnote'
ensure_file() {
  mkdir -p "$(dirname "$FILE")" 2>/dev/null || true
  [ -f "$FILE" ] || printf '%s\n' "$HEADER" > "$FILE"
}

# Replace tabs/newlines in a field so one row stays one row.
clean() { printf '%s' "$1" | tr '\t\n' '  '; }

case "$ACTION" in
  add)
    [ -n "$HOST$SERVICE$USER$SECRET" ] || die "add needs at least one of --host/--service/--user/--secret."
    ensure_file
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ts" "$(clean "$HOST")" "$(clean "$SERVICE")" "$(clean "$USER")" \
      "$(clean "$SECRET")" "$(clean "$SOURCE")" "$(clean "$NOTE")" >> "$FILE"
    echo ">> Added: ${USER:-?}@${HOST:-?} (${SERVICE:-?}) -> $FILE"
    ;;
  list)
    [ -f "$FILE" ] || die "No vault at $FILE yet."
    if command -v column >/dev/null 2>&1; then
      column -t -s $'\t' "$FILE"
    else
      cat "$FILE"
    fi
    ;;
  search)
    [ -n "$TERM" ] || die "search needs a term."
    [ -f "$FILE" ] || die "No vault at $FILE yet."
    { head -n1 "$FILE"; grep -i -- "$TERM" "$FILE" || true; } | \
      { command -v column >/dev/null 2>&1 && column -t -s $'\t' || cat; }
    ;;
  count)
    [ -f "$FILE" ] || die "No vault at $FILE yet."
    n=$(( $(wc -l < "$FILE") - 1 ))
    echo ">> $n credential row(s) in $FILE"
    ;;
esac

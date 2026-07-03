#!/usr/bin/env bash
#
# notes-timestamp.sh
#
# Append timestamped entries to an engagement notes file: either a plain note,
# or a command plus its output. Turns notes.md into a running worklog without
# copy-pasting terminal output by hand.
#
# Usage:
#   ./notes-timestamp.sh "found anonymous FTP on 10.0.0.5"
#   ./notes-timestamp.sh --run "nmap -sV 10.0.0.5"       # logs command + output
#   ./notes-timestamp.sh --file ~/eng/acme/notes/notes.md --run "id"
#   ./notes-timestamp.sh --run "whoami" --quiet          # don't echo to screen
#
# The notes file defaults to $NOTES, then ./notes/notes.md, then ./notes.md.
#
set -uo pipefail

FILE=""
RUN=0
QUIET=0

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --run|-r)   RUN=1 ;;
    --quiet|-q) QUIET=1 ;;
    --file|-f)  shift; [ $# -gt 0 ] || die "--file needs a path"; FILE="$1" ;;
    --file=*)   FILE="${1#*=}" ;;
    --)         shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done; break ;;
    *)          ARGS+=("$1") ;;
  esac
  shift
done
[ "${#ARGS[@]}" -gt 0 ] || { echo "Nothing to log." >&2; usage 2; }

# --- resolve notes file ---------------------------------------------------
if [ -z "$FILE" ]; then
  if   [ -n "${NOTES:-}" ];      then FILE="$NOTES"
  elif [ -f "./notes/notes.md" ]; then FILE="./notes/notes.md"
  else FILE="./notes.md"; fi
fi
mkdir -p "$(dirname "$FILE")" 2>/dev/null || true
[ -f "$FILE" ] || printf '# Notes\n' > "$FILE"

ts=$(date '+%Y-%m-%d %H:%M:%S')

if [ "$RUN" -eq 1 ]; then
  cmd="${ARGS[*]}"
  # Run through a shell so pipes/redirs in the quoted command work.
  output=$(bash -c "$cmd" 2>&1)
  rc=$?
  {
    echo
    echo "### $ts \`$cmd\` (exit $rc)"
    echo '```'
    echo "$output"
    echo '```'
  } >> "$FILE"
  [ "$QUIET" -eq 1 ] || { echo "$output"; }
  echo ">> Logged command to $FILE" >&2
  exit "$rc"
else
  note="${ARGS[*]}"
  echo "- $ts $note" >> "$FILE"
  [ "$QUIET" -eq 1 ] || echo ">> Noted in $FILE"
  exit 0
fi

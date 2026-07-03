#!/usr/bin/env bash
#
# port-monitor.sh
#
# Re-scan a target on an interval and report when open ports change since the
# last scan. Useful on long engagements to catch services that come and go.
#
# Usage:
#   ./port-monitor.sh 10.10.10.10                 # every 5 min until Ctrl-C
#   ./port-monitor.sh target.tld --interval 900   # every 15 min
#   ./port-monitor.sh target.tld --once           # single scan, then exit
#   ./port-monitor.sh target.tld --ports 1-1000   # limit the port range
#
set -uo pipefail

INTERVAL=300
ONCE=0
PORTS="--top-ports 1000"
STATE_DIR=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    --once)        ONCE=1 ;;
    --interval|-i) shift; [ $# -gt 0 ] || die "--interval needs seconds"; INTERVAL="$1" ;;
    --interval=*)  INTERVAL="${1#*=}" ;;
    --ports|-p)    shift; [ $# -gt 0 ] || die "--ports needs a range"; PORTS="-p $1" ;;
    --ports=*)     PORTS="-p ${1#*=}" ;;
    --out|-o)      shift; [ $# -gt 0 ] || die "--out needs a path"; STATE_DIR="$1" ;;
    --out=*)       STATE_DIR="${1#*=}" ;;
    -*)            die "Unknown option: $1 (try --help)" ;;
    *)             [ -z "$TARGET" ] || die "Only one target allowed."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target given." >&2; usage 2; }
have nmap || die "nmap not found."

slug=$(printf '%s' "$TARGET" | tr -cd 'a-zA-Z0-9._-')
[ -n "$STATE_DIR" ] || STATE_DIR="./portmon_${slug}"
mkdir -p "$STATE_DIR" || die "Cannot create $STATE_DIR"
PREV="$STATE_DIR/open-ports.last"
LOG="$STATE_DIR/changes.log"

scan_open_ports() {
  # -T4 fast, -Pn skip host discovery, grep open ports from grepable output.
  nmap -Pn -T4 $PORTS "$TARGET" -oG - 2>/dev/null \
    | grep -oE '[0-9]+/open' | cut -d/ -f1 | sort -un
}

do_cycle() {
  local now cur added removed
  now=$(date '+%Y-%m-%d %H:%M:%S')
  cur=$(scan_open_ports)
  if [ ! -f "$PREV" ]; then
    echo "[$now] baseline: $(echo "$cur" | tr '\n' ' ')"
    echo "[$now] baseline: $(echo "$cur" | tr '\n' ' ')" >> "$LOG"
    echo "$cur" > "$PREV"
    return 0
  fi
  added=$(comm -13 "$PREV" <(echo "$cur"))
  removed=$(comm -23 "$PREV" <(echo "$cur"))
  if [ -z "$added" ] && [ -z "$removed" ]; then
    echo "[$now] no change ($(echo "$cur" | grep -c '' ) open)"
  else
    [ -n "$added" ]   && { echo "[$now] OPENED : $(echo "$added" | tr '\n' ' ')"; echo "[$now] OPENED : $(echo "$added" | tr '\n' ' ')" >> "$LOG"; }
    [ -n "$removed" ] && { echo "[$now] CLOSED : $(echo "$removed" | tr '\n' ' ')"; echo "[$now] CLOSED : $(echo "$removed" | tr '\n' ' ')" >> "$LOG"; }
    echo "$cur" > "$PREV"
  fi
}

echo ">> Monitoring $TARGET  (state: $STATE_DIR)"
[ "$ONCE" -eq 1 ] && { do_cycle; exit 0; }

echo ">> Interval ${INTERVAL}s. Ctrl-C to stop."
while true; do
  do_cycle
  sleep "$INTERVAL"
done

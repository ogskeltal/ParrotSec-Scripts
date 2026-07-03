#!/usr/bin/env bash
#
# shell-upgrade.sh
#
# Print the sequence to turn a raw reverse shell into a full interactive PTY,
# with your current terminal size filled in. Nothing to run against a target;
# it just spits out the commands to paste, in order.
#
# Usage:
#   ./shell-upgrade.sh                 # detect rows/cols from this terminal
#   ./shell-upgrade.sh --rows 50 --cols 200
#
set -uo pipefail

ROWS=""
COLS=""

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    -h|--help) usage 0 ;;
    --rows) j=$((i+1)); ROWS="${!j}" ;;
    --cols) j=$((i+1)); COLS="${!j}" ;;
  esac
done

# Detect terminal size if not given.
if [ -z "$ROWS" ] || [ -z "$COLS" ]; then
  if size=$(stty size 2>/dev/null); then
    ROWS="${ROWS:-${size% *}}"
    COLS="${COLS:-${size#* }}"
  fi
fi
ROWS="${ROWS:-38}"
COLS="${COLS:-190}"

cat <<EOF
=== Upgrade a dumb shell to a full PTY (rows=$ROWS cols=$COLS) ===

# 1) On the target, spawn a PTY (try these in order until one works):
python3 -c 'import pty; pty.spawn("/bin/bash")'
python  -c 'import pty; pty.spawn("/bin/bash")'
script -qc /bin/bash /dev/null

# 2) Background the shell:
#    press Ctrl-Z

# 3) On YOUR box, drop the local terminal into raw mode and foreground it:
stty raw -echo; fg
#    (type 'fg' even though you can't see it, then press Enter)

# 4) Back in the shell, fix the environment and terminal size:
reset
export TERM=xterm-256color
export SHELL=/bin/bash
stty rows $ROWS cols $COLS

# Now Ctrl-C, tab-completion, and less/vim behave normally.
EOF

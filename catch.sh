#!/usr/bin/env bash
#
# catch.sh
#
# Multi-shell catcher. Opens a listener per port in its own tmux window and logs
# everything each shell does to a file, so you can catch several callbacks at
# once without juggling terminals. The receiving end for revshell.sh /
# payload-gen.sh. Falls back to a single foreground listener without tmux.
#
# Usage:
#   ./catch.sh 4444                       # one listener
#   ./catch.sh 4444 4445 9001             # one tmux window per port
#   ./catch.sh 4444 --session hydra --log ~/eng/acme/loot
#   ./catch.sh --attach hydra             # re-attach to a running session
#
set -uo pipefail

SESSION="catch"
LOGDIR="./shell-logs"
ATTACH=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

listener_cmd() { # port logfile -> a shell command string
  local port="$1" log="$2"
  if have rlwrap && have nc; then echo "rlwrap nc -lvnp $port | tee '$log'"
  elif have nc;   then echo "nc -lvnp $port | tee '$log'"
  elif have ncat; then echo "ncat -lvnp $port | tee '$log'"
  else return 1; fi
}

# --- parse args -----------------------------------------------------------
PORTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --session)  shift; [ $# -gt 0 ] || die "--session needs a name"; SESSION="$1" ;;
    --session=*) SESSION="${1#*=}" ;;
    --log)      shift; [ $# -gt 0 ] || die "--log needs a path"; LOGDIR="$1" ;;
    --log=*)    LOGDIR="${1#*=}" ;;
    --attach)   shift; [ $# -gt 0 ] || die "--attach needs a session"; ATTACH="$1" ;;
    -*)         die "Unknown option: $1 (try --help)" ;;
    *)          PORTS+=("$1") ;;
  esac
  shift
done

if [ -n "$ATTACH" ]; then
  have tmux || die "tmux not installed."
  exec tmux attach -t "$ATTACH"
fi

[ "${#PORTS[@]}" -ge 1 ] || { echo "Give at least one port." >&2; usage 2; }
listener_cmd 1 /dev/null >/dev/null || die "Need nc or ncat for listeners."
mkdir -p "$LOGDIR"

# --- single port without tmux: just run it --------------------------------
if [ "${#PORTS[@]}" -eq 1 ] && ! have tmux; then
  p="${PORTS[0]}"; log="$LOGDIR/shell_${p}_$(date +%Y%m%d-%H%M%S).log"
  echo ">> Listening on $p (logging to $log). Ctrl-C to stop."
  cmd=$(listener_cmd "$p" "$log")
  exec bash -c "$cmd"
fi

have tmux || die "Multiple ports need tmux (apt install tmux)."

# --- tmux: one window per port --------------------------------------------
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo ">> Reusing existing tmux session '$SESSION'."
else
  tmux new-session -d -s "$SESSION" -n scratch
fi

for p in "${PORTS[@]}"; do
  log="$LOGDIR/shell_${p}_$(date +%Y%m%d-%H%M%S).log"
  cmd=$(listener_cmd "$p" "$log")
  tmux new-window -t "$SESSION" -n "port-$p" "echo '>> listener on $p (log: $log)'; $cmd; echo '>> listener $p exited'; exec bash"
  echo ">> listener queued on $p  (log: $log)"
done
tmux kill-window -t "$SESSION:scratch" 2>/dev/null || true

echo
echo ">> ${#PORTS[@]} listener(s) running in tmux session '$SESSION'."
echo ">> Attach: tmux attach -t $SESSION    (or: $0 --attach $SESSION)"
echo ">> Switch windows: Ctrl-b then a window number."

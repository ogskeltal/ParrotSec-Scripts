#!/usr/bin/env bash
#
# dashboard.sh
#
# One-screen engagement status: workspace, credential count, pivot/killswitch/
# anonymize state, VPN interface, and the last port-monitor change. Read-only,
# no root. Ties together the state left by the other scripts.
#
# Usage:
#   ./dashboard.sh                       # use the current directory as workspace
#   ./dashboard.sh ~/engagements/acme    # point at a workspace
#   ./dashboard.sh --exit-ip             # also fetch the current external IP
#
set -uo pipefail

STATE_DIR="/var/lib/parrot-scripts"
PIVOT_STATE="${PIVOT_STATE:-$HOME/.local/share/parrot-pivot}"
SHOW_EXIT_IP=0

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

WS="."
for arg in "$@"; do
  case "$arg" in
    -h|--help)   usage 0 ;;
    --exit-ip)   SHOW_EXIT_IP=1 ;;
    -*)          echo "Unknown option: $arg" >&2; usage 2 ;;
    *)           WS="$arg" ;;
  esac
done

hr() { printf '%s\n' "----------------------------------------"; }
row() { printf '  %-14s %s\n' "$1" "$2"; }

echo "========================================"
echo "  ENGAGEMENT DASHBOARD  $(date '+%Y-%m-%d %H:%M')"
echo "========================================"

# --- workspace ------------------------------------------------------------
echo "[ workspace ]"
row "path" "$(cd "$WS" 2>/dev/null && pwd || echo "$WS")"
if [ -f "$WS/scope.txt" ]; then
  scope=$(grep -vE '^\s*#|^\s*$' "$WS/scope.txt" | head -n3 | tr '\n' ' ')
  row "scope" "${scope:-'(empty)'}"
fi
for sub in scans web loot notes; do
  [ -d "$WS/$sub" ] && row "$sub/" "$(find "$WS/$sub" -type f 2>/dev/null | grep -c '') files"
done

# --- credentials ----------------------------------------------------------
hr; echo "[ credentials ]"
vault=""
for c in "${CREDS_VAULT:-}" "$WS/creds/vault.tsv" "./creds/vault.tsv"; do
  [ -n "$c" ] && [ -f "$c" ] && { vault="$c"; break; }
done
if [ -n "$vault" ]; then
  row "vault" "$vault"
  row "entries" "$(( $(wc -l < "$vault") - 1 ))"
else
  row "vault" "none found"
fi

# --- opsec state ----------------------------------------------------------
hr; echo "[ opsec ]"
if [ -f "$STATE_DIR/killswitch.v4.rules" ]; then row "killswitch" "ACTIVE"; else row "killswitch" "off"; fi
if [ -f "$STATE_DIR/anonymize.macs" ];   then row "anonymize"  "ACTIVE (MAC/host spoofed)"; else row "anonymize" "off"; fi
if have anonsurf; then row "anonsurf" "$(anonsurf status 2>/dev/null | head -n1 || echo unknown)"; fi

# --- pivot ----------------------------------------------------------------
hr; echo "[ pivot ]"
if [ -f "$PIVOT_STATE/pivot.pid" ] && kill -0 "$(cat "$PIVOT_STATE/pivot.pid")" 2>/dev/null; then
  row "pivot" "running (pid $(cat "$PIVOT_STATE/pivot.pid"))"
  [ -f "$PIVOT_STATE/proxychains.conf" ] && row "socks" "$(grep -E '^socks' "$PIVOT_STATE/proxychains.conf" | tail -n1)"
else
  row "pivot" "not running"
fi

# --- network --------------------------------------------------------------
hr; echo "[ network ]"
for ifc in tun0 wg0 ppp0; do
  if [ -d "/sys/class/net/$ifc" ]; then
    ipaddr=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4}' | head -n1)
    row "$ifc" "${ipaddr:-up}"
  fi
done
if [ "$SHOW_EXIT_IP" -eq 1 ] && have curl; then
  row "exit IP" "$(curl -s --max-time 6 https://ifconfig.me 2>/dev/null || echo 'lookup failed')"
fi

# --- last port-monitor change --------------------------------------------
hr; echo "[ port-monitor ]"
last_log=$(find . "$WS" -maxdepth 2 -name changes.log 2>/dev/null | head -n1 || true)
if [ -n "$last_log" ]; then
  row "log" "$last_log"
  tail -n2 "$last_log" | sed 's/^/    /'
else
  row "changes" "none tracked"
fi

echo "========================================"

#!/usr/bin/env bash
#
# healthcheck.sh
#
# One-screen health of the local Parrot box: disk, memory, load, failed systemd
# units, pending updates, kernel/reboot status, and whether the opsec scripts
# (killswitch/anonymize) are active. Read-only, no root needed.
#
# Usage:
#   ./healthcheck.sh
#
set -uo pipefail

STATE_DIR="/var/lib/parrot-scripts"
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

case "${1:-}" in -h|--help) usage 0 ;; esac

hr() { printf '%s\n' "----------------------------------------"; }
row() { printf '  %-16s %s\n' "$1" "$2"; }

echo "========================================"
echo "  PARROT HEALTHCHECK  $(date '+%Y-%m-%d %H:%M')"
echo "========================================"

# --- disk -----------------------------------------------------------------
echo "[ disk ]"
df -h --output=target,pcent,avail / /home 2>/dev/null | tail -n +2 | while read -r tgt pct avail; do
  flag=""; n="${pct%\%}"; [ "${n:-0}" -ge 90 ] 2>/dev/null && flag="  [!] low space"
  row "$tgt" "$pct used, $avail free$flag"
done

# --- memory / load --------------------------------------------------------
hr; echo "[ memory / load ]"
if have free; then row "memory" "$(free -h | awk '/^Mem:/{print $3" used / "$2" total, "$7" avail"}')"; fi
if have free; then
  swap=$(free -h | awk '/^Swap:/{print $3" / "$2}'); row "swap" "$swap"
fi
row "load" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null) (1/5/15 min)"
row "uptime" "$(uptime -p 2>/dev/null | sed 's/^up //')"

# --- systemd --------------------------------------------------------------
hr; echo "[ services ]"
if have systemctl; then
  failed=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}')
  if [ -n "$failed" ]; then
    row "failed units" "$(echo "$failed" | grep -c '')"
    echo "$failed" | sed 's/^/       /'
  else
    row "failed units" "none"
  fi
fi

# --- updates --------------------------------------------------------------
hr; echo "[ updates ]"
if have apt-get; then
  # -s simulate; count upgradable without touching anything.
  up=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)
  row "pending" "$up package(s) upgradable"
  [ "$up" -gt 0 ] && row "" "run: sudo ./update-parrot.sh"
fi
if [ -f /var/run/reboot-required ]; then row "reboot" "REQUIRED"; else
  running=$(uname -r); newest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n1)
  if [ -n "$newest" ] && [ "$newest" != "$running" ]; then row "reboot" "recommended (kernel $newest)"; else row "reboot" "not needed"; fi
fi

# --- opsec ----------------------------------------------------------------
hr; echo "[ opsec ]"
[ -f "$STATE_DIR/killswitch.v4.rules" ] && row "killswitch" "ACTIVE" || row "killswitch" "off"
[ -f "$STATE_DIR/anonymize.macs" ]      && row "anonymize"  "ACTIVE" || row "anonymize" "off"

echo "========================================"

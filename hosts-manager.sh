#!/usr/bin/env bash
#
# hosts-manager.sh
#
# Add and remove target vhosts in /etc/hosts, tagged per engagement so you can
# clear them all at once. Backs up /etc/hosts before changing it.
#
# Usage:
#   sudo ./hosts-manager.sh add 10.10.10.5 dc01.corp.local corp.local --tag htb
#   sudo ./hosts-manager.sh remove dc01.corp.local
#   sudo ./hosts-manager.sh clear-tag htb
#   ./hosts-manager.sh list                       # no root
#
set -uo pipefail

HOSTS="/etc/hosts"
BACKUP_DIR="/var/lib/parrot-scripts"
TAG="manual"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

need_root() { [ "$(id -u)" -eq 0 ] || die "'$1' edits $HOSTS and needs root."; }
backup() { mkdir -p "$BACKUP_DIR"; cp "$HOSTS" "$BACKUP_DIR/hosts.$(date +%Y%m%d-%H%M%S).bak"; }

# --- parse args -----------------------------------------------------------
ACTION=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --tag)      shift; [ $# -gt 0 ] || die "--tag needs a value"; TAG="$1" ;;
    --tag=*)    TAG="${1#*=}" ;;
    add|remove|list|clear-tag)
      [ -z "$ACTION" ] || die "One action at a time."; ACTION="$1" ;;
    *)          ARGS+=("$1") ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "No action (add|remove|list|clear-tag)." >&2; usage 2; }

case "$ACTION" in
  add)
    need_root add
    [ "${#ARGS[@]}" -ge 2 ] || die "add needs: <ip> <hostname> [more hostnames...]"
    ip="${ARGS[0]}"
    names="${ARGS[*]:1}"
    backup
    # Drop any existing line for these names to avoid duplicates.
    for n in $names; do
      sed -i "/[[:space:]]${n//./\\.}\([[:space:]]\|$\)/d" "$HOSTS"
    done
    printf '%s\t%s\t# parrot-hosts:%s\n' "$ip" "$names" "$TAG" >> "$HOSTS"
    echo ">> Added: $ip -> $names  [tag: $TAG]"
    ;;
  remove)
    need_root remove
    [ "${#ARGS[@]}" -ge 1 ] || die "remove needs a hostname."
    backup
    for n in "${ARGS[@]}"; do
      sed -i "/[[:space:]]${n//./\\.}\([[:space:]]\|$\)/d" "$HOSTS"
      echo ">> Removed lines matching: $n"
    done
    ;;
  clear-tag)
    need_root clear-tag
    [ "${#ARGS[@]}" -ge 1 ] || die "clear-tag needs a tag name."
    backup
    sed -i "/# parrot-hosts:${ARGS[0]}$/d" "$HOSTS"
    echo ">> Cleared all entries tagged '${ARGS[0]}'."
    ;;
  list)
    echo ">> parrot-hosts entries in $HOSTS:"
    grep -n "# parrot-hosts:" "$HOSTS" 2>/dev/null | sed 's/^/   /' || echo "   (none)"
    ;;
esac

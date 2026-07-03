#!/usr/bin/env bash
#
# cleanup-parrot.sh
#
# Reclaim disk space: apt cache, orphaned packages, old kernels, journal logs,
# thumbnail cache, and trash. Shows a before/after free-space summary. Preview
# with --dry-run first.
#
# Usage:
#   ./cleanup-parrot.sh --dry-run       # show what would be freed
#   sudo ./cleanup-parrot.sh            # do it
#   sudo ./cleanup-parrot.sh --journal 200M --keep-kernels 2
#
set -uo pipefail

DRY_RUN=0
JOURNAL_KEEP="200M"
KEEP_KERNELS=2

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

for arg in "$@"; do
  case "$arg" in
    -h|--help)        usage 0 ;;
    --dry-run|-n)     DRY_RUN=1 ;;
    --journal=*)      JOURNAL_KEEP="${arg#*=}" ;;
    --keep-kernels=*) KEEP_KERNELS="${arg#*=}" ;;
    *)                die "Unknown option: $arg (try --help)" ;;
  esac
done

have apt-get || die "apt-get not found. This is for Parrot/Debian."
if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
  die "Cleaning needs root. Re-run with sudo (or --dry-run)."
fi

free_root() { df -h --output=avail / | tail -n1 | tr -d ' '; }
before=$(free_root)
echo ">> Free space on / before: $before"
export DEBIAN_FRONTEND=noninteractive

# --- apt ------------------------------------------------------------------
echo ">> apt autoremove + clean..."
run apt-get -y autoremove --purge
run apt-get -y autoclean
run apt-get -y clean

# --- old kernels ----------------------------------------------------------
echo ">> Old kernels (keeping newest $KEEP_KERNELS + running)..."
running=$(uname -r)
mapfile -t installed < <(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | sort -V)
if [ "${#installed[@]}" -gt "$KEEP_KERNELS" ]; then
  # Candidates for removal: everything except the newest N and the running one.
  drop=$(printf '%s\n' "${installed[@]}" | head -n "$(( ${#installed[@]} - KEEP_KERNELS ))")
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    case "$k" in *"$running"*) continue ;; esac
    echo "   remove: $k"
    run apt-get -y purge "$k"
  done <<< "$drop"
else
  echo "   nothing to remove."
fi

# --- journal --------------------------------------------------------------
if have journalctl; then
  echo ">> Vacuuming systemd journal to $JOURNAL_KEEP..."
  run journalctl --vacuum-size="$JOURNAL_KEEP"
fi

# --- caches / trash -------------------------------------------------------
echo ">> Thumbnail cache and trash..."
[ -d "$HOME/.cache/thumbnails" ] && run rm -rf "$HOME/.cache/thumbnails/"* 2>/dev/null
for t in "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info"; do
  [ -d "$t" ] && run rm -rf "${t:?}/"* 2>/dev/null
done

after=$(free_root)
echo
echo "================ SUMMARY ================"
echo "Free on / before : $before"
echo "Free on / after  : $after"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run: nothing was actually removed)"
echo "========================================"

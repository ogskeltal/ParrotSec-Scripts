#!/usr/bin/env bash
#
# panic-wipe.sh
#
# DESTRUCTIVE. Securely removes engagement data and clears history/traces.
# Nothing happens without an explicit action flag AND a typed confirmation.
# Always dry-run first.
#
# Actions (pick at least one; nothing is wiped by default):
#   --loot DIR     shred every file under DIR, then remove DIR
#   --history      clear shell history (bash/zsh) and common tool history
#   --clipboard    clear the X clipboard/primary selection
#   --caches       drop kernel page/dentry caches (needs root)
#   --all          all of the above (still needs --loot DIR for the loot step)
#
# Options:
#   --dry-run, -n  show exactly what would be wiped, touch nothing
#   --yes          skip the typed confirmation (for scripted use; dangerous)
#   -h, --help
#
# Examples:
#   ./panic-wipe.sh --loot ~/engagements/acme_2026-07-03 --dry-run
#   ./panic-wipe.sh --loot ~/engagements/acme_2026-07-03 --history --clipboard
#   sudo ./panic-wipe.sh --all --loot ~/engagements/acme_2026-07-03
#
set -uo pipefail

LOOT_DIR=""
DO_HISTORY=0
DO_CLIP=0
DO_CACHES=0
DRY_RUN=0
ASSUME_YES=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

say() { echo ">> $*"; }
act() {  # echo in dry-run, execute otherwise
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] $*"; return 0; fi
  "$@"
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --yes)        ASSUME_YES=1 ;;
    --history)    DO_HISTORY=1 ;;
    --clipboard)  DO_CLIP=1 ;;
    --caches)     DO_CACHES=1 ;;
    --all)        DO_HISTORY=1; DO_CLIP=1; DO_CACHES=1 ;;
    --loot)       shift; [ $# -gt 0 ] || die "--loot needs a directory"; LOOT_DIR="$1" ;;
    --loot=*)     LOOT_DIR="${1#*=}" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

DO_LOOT=0
[ -n "$LOOT_DIR" ] && DO_LOOT=1

if [ "$DO_LOOT" -eq 0 ] && [ "$DO_HISTORY" -eq 0 ] && [ "$DO_CLIP" -eq 0 ] && [ "$DO_CACHES" -eq 0 ]; then
  echo "No action given. Pick at least one: --loot DIR, --history, --clipboard, --caches." >&2
  usage 2
fi

# --- validate loot target so we never wipe something critical -------------
if [ "$DO_LOOT" -eq 1 ]; then
  [ -d "$LOOT_DIR" ] || die "Loot directory not found: $LOOT_DIR"
  # Resolve to an absolute, real path.
  LOOT_ABS=$(cd "$LOOT_DIR" 2>/dev/null && pwd -P) || die "Cannot resolve $LOOT_DIR"
  case "$LOOT_ABS" in
    /|/home|/root|"$HOME"|/etc|/usr|/var|/bin|/boot|/lib*|/opt|/sys|/proc)
      die "Refusing to wipe a protected path: $LOOT_ABS" ;;
  esac
  # Require a reasonably deep path so a stray value can't nuke a top-level dir.
  depth=$(awk -F/ '{print NF-1}' <<< "$LOOT_ABS")
  [ "$depth" -ge 2 ] || die "Refusing to wipe a shallow path ($LOOT_ABS). Point --loot at an engagement subdir."
fi

# --- show the plan --------------------------------------------------------
echo "================ PLAN ================"
[ "$DO_LOOT"    -eq 1 ] && echo " * shred + remove : $LOOT_ABS"
[ "$DO_HISTORY" -eq 1 ] && echo " * clear history  : shell + tool history files"
[ "$DO_CLIP"    -eq 1 ] && echo " * clear clipboard"
[ "$DO_CACHES"  -eq 1 ] && echo " * drop caches    : /proc/sys/vm/drop_caches (needs root)"
echo "======================================"
echo

# --- confirmation ---------------------------------------------------------
if [ "$DRY_RUN" -ne 1 ] && [ "$ASSUME_YES" -ne 1 ]; then
  echo "This is destructive and cannot be undone."
  printf 'Type WIPE to proceed: '
  read -r reply
  [ "$reply" = "WIPE" ] || die "Not confirmed. Aborting."
fi

wiped_files=0

# --- loot -----------------------------------------------------------------
if [ "$DO_LOOT" -eq 1 ]; then
  say "Wiping loot at $LOOT_ABS"
  if have shred; then
    while IFS= read -r -d '' f; do
      act shred -uz "$f" && wiped_files=$((wiped_files+1))
    done < <(find "$LOOT_ABS" -type f -print0)
  else
    say "shred not found; falling back to rm (files not securely overwritten)."
  fi
  act rm -rf "$LOOT_ABS"
fi

# --- history --------------------------------------------------------------
if [ "$DO_HISTORY" -eq 1 ]; then
  say "Clearing shell and tool history"
  HIST_FILES=(
    "$HOME/.bash_history"
    "$HOME/.zsh_history"
    "$HOME/.local/share/fish/fish_history"
    "$HOME/.msf4/history"
    "$HOME/.sqlmap/history"
    "$HOME/.python_history"
    "$HOME/.lesshst"
  )
  for hf in "${HIST_FILES[@]}"; do
    if [ -f "$hf" ]; then
      if have shred; then act shred -uz "$hf"; else act rm -f "$hf"; fi
    fi
  done
  # Truncate the current session's in-memory history too.
  if [ "$DRY_RUN" -ne 1 ]; then history -c 2>/dev/null || true; fi
fi

# --- clipboard ------------------------------------------------------------
if [ "$DO_CLIP" -eq 1 ]; then
  say "Clearing clipboard"
  if have xsel; then
    act xsel -bc; act xsel -pc
  elif have xclip; then
    if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] xclip clear"; else printf '' | xclip -selection clipboard; fi
  else
    say "No xsel/xclip; skipping clipboard."
  fi
fi

# --- caches ---------------------------------------------------------------
if [ "$DO_CACHES" -eq 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    say "Skipping cache drop (needs root)."
  else
    say "Dropping caches"
    act sync
    if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] echo 3 > /proc/sys/vm/drop_caches"; else echo 3 > /proc/sys/vm/drop_caches; fi
  fi
fi

echo
echo "================ DONE ================"
[ "$DO_LOOT" -eq 1 ] && echo "Files shredded : $wiped_files"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run: nothing was actually changed)"
echo "====================================="

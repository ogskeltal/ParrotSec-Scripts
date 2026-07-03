#!/usr/bin/env bash
#
# dotfiles-sync.sh
#
# Back up and restore your tool configs and dotfiles so a fresh Parrot install
# is a quick restore away. Copies a curated set into a backup directory (a git
# repo if you want history); restore copies them back.
#
# Usage:
#   ./dotfiles-sync.sh backup                    # into ./dotfiles-backup
#   ./dotfiles-sync.sh backup --dir ~/dotfiles --git
#   ./dotfiles-sync.sh restore --dir ~/dotfiles
#   ./dotfiles-sync.sh list
#   ./dotfiles-sync.sh backup --dry-run
#
# WARNING: some of these files hold secrets (API keys, msf db creds). Keep the
# backup private; don't push it to a public repo.
#
set -uo pipefail

DIR="./dotfiles-backup"
USE_GIT=0
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

# Paths are relative to $HOME.
ITEMS=(
  ".bashrc" ".bash_aliases" ".zshrc" ".profile"
  ".tmux.conf" ".vimrc" ".gitconfig" ".nanorc"
  ".config/proxychains/proxychains.conf"
  ".msf4/msfconsole.rc"
  ".config/nvim"
  ".ssh/config"
  ".searchsploit_rc"
  ".config/starship.toml"
)

# --- parse args -----------------------------------------------------------
ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dir)        shift; [ $# -gt 0 ] || die "--dir needs a path"; DIR="$1" ;;
    --dir=*)      DIR="${1#*=}" ;;
    --git)        USE_GIT=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    backup|restore|list)
      [ -z "$ACTION" ] || die "One action at a time."; ACTION="$1" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "No action (backup|restore|list)." >&2; usage 2; }

case "$ACTION" in
  list)
    echo ">> Tracked dotfiles (present ones marked *):"
    for it in "${ITEMS[@]}"; do
      [ -e "$HOME/$it" ] && echo "   * $it" || echo "     $it"
    done
    ;;
  backup)
    run mkdir -p "$DIR"
    echo ">> Backing up into $DIR"
    n=0
    for it in "${ITEMS[@]}"; do
      src="$HOME/$it"
      [ -e "$src" ] || continue
      dest="$DIR/$it"
      run mkdir -p "$(dirname "$dest")"
      if [ -d "$src" ]; then run cp -a "$src/." "$dest/"; else run cp -a "$src" "$dest"; fi
      echo "   + $it"; n=$((n+1))
    done
    echo ">> Backed up $n item(s)."
    if [ "$USE_GIT" -eq 1 ] && have git; then
      ( cd "$DIR" && run git init -q 2>/dev/null; run git add -A; run git commit -q -m "dotfiles backup $(date +%Y-%m-%d)" 2>/dev/null || true )
      echo ">> Committed to git repo in $DIR"
    fi
    ;;
  restore)
    [ -d "$DIR" ] || die "Backup dir not found: $DIR"
    echo ">> Restoring from $DIR into \$HOME"
    n=0
    for it in "${ITEMS[@]}"; do
      src="$DIR/$it"
      [ -e "$src" ] || continue
      dest="$HOME/$it"
      run mkdir -p "$(dirname "$dest")"
      # Back up an existing target before overwriting.
      [ -e "$dest" ] && run cp -a "$dest" "${dest}.pre-restore" 2>/dev/null
      if [ -d "$src" ]; then run cp -a "$src/." "$dest/"; else run cp -a "$src" "$dest"; fi
      echo "   -> $it"; n=$((n+1))
    done
    echo ">> Restored $n item(s). Existing files were saved as *.pre-restore."
    ;;
esac

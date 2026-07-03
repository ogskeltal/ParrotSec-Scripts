#!/usr/bin/env bash
#
# wordlists-setup.sh
#
# Populate a wordlists directory on Parrot. Unpacks the system rockyou.txt if
# present, then clones a set of well-known wordlist repos from GitHub. Existing
# clones are updated (git pull) instead of re-cloned, so re-running is cheap.
#
# Usage:
#   ./wordlists-setup.sh                 # unpack rockyou + clone the core repos
#   ./wordlists-setup.sh --large         # also clone the very large repos
#   ./wordlists-setup.sh --dir ~/wl      # install into a custom directory
#   ./wordlists-setup.sh --list          # show the repo set and exit
#   ./wordlists-setup.sh --dry-run       # show what would happen, change nothing
#
# The default directory is /usr/share/wordlists when writable (needs root),
# otherwise ~/wordlists. Override with --dir.
#
set -uo pipefail

# name|git-url|size-tag|description
# size-tag: core (cloned by default) or large (needs --large)
REPOS=(
  "SecLists|https://github.com/danielmiessler/SecLists.git|core|The standard collection: users, passwords, fuzzing, discovery"
  "PayloadsAllTheThings|https://github.com/swisskyrepo/PayloadsAllTheThings.git|core|Payloads and bypasses per vulnerability class"
  "fuzzdb|https://github.com/fuzzdb-project/fuzzdb.git|core|Attack patterns for fault injection and discovery"
  "kkrypt0nn-wordlists|https://github.com/kkrypt0nn/wordlists.git|core|General discovery/enumeration wordlists"
  "fuzz.txt|https://github.com/Bo0oM/fuzz.txt.git|core|Potentially dangerous file/path list for content discovery"
  "wpa2-wordlists|https://github.com/kennyn510/wpa2-wordlists.git|core|WPA2 handshake cracking dictionaries"
  "Probable-Wordlists|https://github.com/berzerk0/Probable-Wordlists.git|large|Passwords sorted by real-world probability (very large)"
  "assetnote-wordlists|https://github.com/assetnote/wordlists.git|large|Monthly content/subdomain discovery lists (very large)"
)

DRY_RUN=0
INCLUDE_LARGE=0
TARGET_DIR=""

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
want_list=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --large)      INCLUDE_LARGE=1 ;;
    --list)       want_list=1 ;;
    --dir)        shift; [ $# -gt 0 ] || die "--dir needs a path"; TARGET_DIR="$1" ;;
    --dir=*)      TARGET_DIR="${1#*=}" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

if [ "$want_list" -eq 1 ]; then
  printf '%-24s %-6s %s\n' "NAME" "SIZE" "DESCRIPTION"
  for entry in "${REPOS[@]}"; do
    IFS='|' read -r name url size desc <<< "$entry"
    printf '%-24s %-6s %s\n' "$name" "$size" "$desc"
  done
  echo
  echo "core repos clone by default; large repos need --large."
  exit 0
fi

have git || die "git not found. Install it: sudo apt-get install -y git"

# --- resolve target dir ---------------------------------------------------
if [ -z "$TARGET_DIR" ]; then
  if [ -w /usr/share/wordlists ] || [ "$(id -u)" -eq 0 ]; then
    TARGET_DIR="/usr/share/wordlists"
  else
    TARGET_DIR="$HOME/wordlists"
  fi
fi
echo ">> Target directory: $TARGET_DIR"
run mkdir -p "$TARGET_DIR" || die "Cannot create $TARGET_DIR (try sudo, or --dir)."

# --- unpack system rockyou if present -------------------------------------
ROCKYOU_GZ="/usr/share/wordlists/rockyou.txt.gz"
if [ -f "$ROCKYOU_GZ" ]; then
  dest="$TARGET_DIR/rockyou.txt"
  if [ -f "$dest" ]; then
    echo ">> rockyou.txt already present, skipping."
  else
    echo ">> Unpacking rockyou.txt..."
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "   [dry-run] gunzip -c $ROCKYOU_GZ > $dest"
    else
      gunzip -c "$ROCKYOU_GZ" > "$dest" || echo "   !! failed to unpack rockyou"
    fi
  fi
else
  echo ">> $ROCKYOU_GZ not found (install the 'wordlists' package for rockyou)."
fi

# --- clone / update repos -------------------------------------------------
cloned=0; updated=0; skipped=0; failed=()

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url size desc <<< "$entry"
  if [ "$size" = "large" ] && [ "$INCLUDE_LARGE" -ne 1 ]; then
    echo ">> Skipping $name (large; pass --large to include)."
    skipped=$((skipped+1))
    continue
  fi

  dest="$TARGET_DIR/$name"
  if [ -d "$dest/.git" ]; then
    echo ">> Updating $name..."
    if run git -C "$dest" pull --ff-only; then
      updated=$((updated+1))
    else
      failed+=("$name")
    fi
  else
    echo ">> Cloning $name..."
    if run git clone --depth 1 "$url" "$dest"; then
      cloned=$((cloned+1))
    else
      failed+=("$name")
    fi
  fi
done

# --- summary --------------------------------------------------------------
echo
echo "================ SUMMARY ================"
echo "Directory : $TARGET_DIR"
echo "Cloned    : $cloned"
echo "Updated   : $updated"
echo "Skipped   : $skipped"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "Failed    : ${#failed[@]}"
  printf '   %s\n' "${failed[@]}"
  echo "Re-run to retry; GitHub or mirror hiccups are the usual cause."
  echo "========================================"
  exit 1
fi
echo "========================================"
exit 0

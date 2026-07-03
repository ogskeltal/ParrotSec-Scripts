#!/usr/bin/env bash
#
# workspace.sh
#
# Scaffold an engagement directory: dated folder with the usual subdirs plus a
# notes template and a scope file. Saves the setup you'd otherwise redo at the
# start of every engagement.
#
# Usage:
#   ./workspace.sh acme-corp                 # ./acme-corp_YYYY-MM-DD/
#   ./workspace.sh acme --base ~/engagements # under a chosen base directory
#   ./workspace.sh acme --no-date            # no date suffix
#   ./workspace.sh acme --force              # populate even if the dir exists
#
set -uo pipefail

BASE="."
ADD_DATE=1
FORCE=0

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# --- parse args -----------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --base)     shift; [ $# -gt 0 ] || die "--base needs a path"; BASE="$1" ;;
    --base=*)   BASE="${1#*=}" ;;
    --no-date)  ADD_DATE=0 ;;
    --force|-f) FORCE=1 ;;
    -*)         die "Unknown option: $1 (try --help)" ;;
    *)          [ -z "$TARGET" ] || die "Only one target name allowed."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target name given." >&2; usage 2; }

# Sanitize the target into a safe directory component.
slug=$(printf '%s' "$TARGET" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-')
[ -n "$slug" ] || die "Target name produced an empty slug."

if [ "$ADD_DATE" -eq 1 ]; then
  dirname="${slug}_$(date +%Y-%m-%d)"
else
  dirname="$slug"
fi
root="${BASE%/}/$dirname"

if [ -d "$root" ] && [ "$FORCE" -ne 1 ]; then
  die "$root already exists. Use --force to populate it anyway."
fi

echo ">> Creating workspace at: $root"
mkdir -p \
  "$root/recon" \
  "$root/scans" \
  "$root/exploits" \
  "$root/loot" \
  "$root/loot/creds" \
  "$root/report" \
  "$root/notes"

# scope.txt: only write if missing, so --force never clobbers real content.
if [ ! -f "$root/scope.txt" ]; then
  cat > "$root/scope.txt" <<EOF
# Scope for ${TARGET}
# One target per line. In-scope hosts, CIDRs, and domains.
# Note any explicit exclusions and the rules of engagement.

EOF
fi

if [ ! -f "$root/notes/notes.md" ]; then
  cat > "$root/notes/notes.md" <<EOF
# ${TARGET} - engagement notes

Created: $(date +%Y-%m-%d)

## Scope
See ../scope.txt

## Recon

## Enumeration

## Findings

## Credentials
See ../loot/creds/

## Loose ends / TODO
EOF
fi

if [ ! -f "$root/README.md" ]; then
  cat > "$root/README.md" <<EOF
# ${TARGET}

| Path         | Contents                                   |
| ------------ | ------------------------------------------ |
| recon/       | passive and active recon output            |
| scans/       | nmap, nuclei, and other scanner output     |
| exploits/    | PoCs and exploit code                      |
| loot/        | extracted files, dumps                     |
| loot/creds/  | credentials and hashes                     |
| report/      | deliverables and write-up                  |
| notes/       | running notes (notes.md)                   |
| scope.txt    | in-scope targets and rules of engagement   |
EOF
fi

echo ">> Layout:"
if command -v tree >/dev/null 2>&1; then
  tree -a "$root"
else
  find "$root" -print | sed "s|^$root|.|" | sort
fi

echo
echo ">> Done. Fill in $root/scope.txt before you start."

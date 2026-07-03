#!/usr/bin/env bash
#
# crack.sh
#
# Wrapper around hashcat. Identifies the hash type (hashid / hashcat --identify),
# picks a wordlist, and runs a straight dictionary attack with an optional rules
# pass. Meant to get a run started fast with sane defaults, not to replace
# hand-tuned hashcat commands.
#
# Usage:
#   ./crack.sh hashes.txt                      # identify, then crack with rockyou
#   ./crack.sh hashes.txt --type 1000          # force mode (NTLM here)
#   ./crack.sh hashes.txt --wordlist ~/wl/x.txt
#   ./crack.sh hashes.txt --rules best64       # apply a rules file
#   ./crack.sh hashes.txt --identify           # just show candidate modes, exit
#   ./crack.sh hashes.txt --dry-run            # print the hashcat command only
#
set -uo pipefail

WORDLIST=""
RULES=""
MODE=""
IDENTIFY_ONLY=0
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# Common wordlist locations, best first.
default_wordlist() {
  local c
  for c in \
    /usr/share/wordlists/rockyou.txt \
    "$HOME/wordlists/rockyou.txt" \
    /usr/share/wordlists/rockyou.txt.gz; do
    if [ -f "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}

# Resolve a rules file from a short name or a path.
resolve_rules() {
  local r="$1"
  [ -f "$r" ] && { echo "$r"; return 0; }
  local d
  for d in /usr/share/hashcat/rules /usr/share/doc/hashcat/rules; do
    [ -f "$d/${r}.rule" ] && { echo "$d/${r}.rule"; return 0; }
    [ -f "$d/${r}" ]      && { echo "$d/${r}"; return 0; }
  done
  return 1
}

# --- parse args -----------------------------------------------------------
HASHFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    --dry-run|-n)  DRY_RUN=1 ;;
    --identify)    IDENTIFY_ONLY=1 ;;
    --type|-m)     shift; [ $# -gt 0 ] || die "--type needs a mode number"; MODE="$1" ;;
    --type=*)      MODE="${1#*=}" ;;
    --wordlist|-w) shift; [ $# -gt 0 ] || die "--wordlist needs a path"; WORDLIST="$1" ;;
    --wordlist=*)  WORDLIST="${1#*=}" ;;
    --rules|-r)    shift; [ $# -gt 0 ] || die "--rules needs a name/path"; RULES="$1" ;;
    --rules=*)     RULES="${1#*=}" ;;
    -*)            die "Unknown option: $1 (try --help)" ;;
    *)             [ -z "$HASHFILE" ] || die "Only one hash file allowed."; HASHFILE="$1" ;;
  esac
  shift
done

[ -n "$HASHFILE" ] || { echo "No hash file given." >&2; usage 2; }
[ -f "$HASHFILE" ] || die "Hash file not found: $HASHFILE"

# --- identify hash type ---------------------------------------------------
show_candidates() {
  if have hashid; then
    echo ">> hashid candidates (first hash):"
    hashid -m "$(head -n1 "$HASHFILE")" 2>/dev/null | sed 's/^/   /' || true
  fi
  if have hashcat; then
    echo ">> hashcat --identify:"
    hashcat --identify "$HASHFILE" 2>/dev/null | sed 's/^/   /' || echo "   (hashcat could not identify it)"
  fi
}

if [ "$IDENTIFY_ONLY" -eq 1 ]; then
  show_candidates
  echo
  echo ">> Re-run with --type <mode> once you've picked one."
  exit 0
fi

have hashcat || die "hashcat not found. Install it: sudo apt-get install -y hashcat"

if [ -z "$MODE" ]; then
  echo ">> No --type given; trying to identify the hash..."
  show_candidates
  echo
  die "Ambiguous or unknown hash type. Re-run with --type <mode> (see candidates above)."
fi

# --- resolve wordlist -----------------------------------------------------
if [ -z "$WORDLIST" ]; then
  WORDLIST=$(default_wordlist) || die "No wordlist found. Pass --wordlist, or run wordlists-setup.sh."
fi
[ -f "$WORDLIST" ] || die "Wordlist not found: $WORDLIST"

# rockyou often ships gzipped; hashcat can't read .gz directly.
if [ "${WORDLIST##*.}" = "gz" ]; then
  die "Wordlist is gzipped ($WORDLIST). Unpack it first (wordlists-setup.sh does this)."
fi

# --- resolve rules --------------------------------------------------------
RULES_ARG=()
if [ -n "$RULES" ]; then
  rpath=$(resolve_rules "$RULES") || die "Rules file not found: $RULES"
  RULES_ARG=(-r "$rpath")
  echo ">> Using rules: $rpath"
fi

# --- build and run --------------------------------------------------------
CMD=(hashcat -m "$MODE" -a 0 "$HASHFILE" "$WORDLIST" "${RULES_ARG[@]}")

echo ">> Mode      : $MODE"
echo ">> Wordlist  : $WORDLIST"
echo ">> Command   : ${CMD[*]}"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  echo ">> Dry run; not launching hashcat."
  exit 0
fi

"${CMD[@]}"
rc=$?

echo
if [ "$rc" -eq 0 ]; then
  echo ">> hashcat finished. Recovered hashes:"
  hashcat -m "$MODE" "$HASHFILE" --show 2>/dev/null | sed 's/^/   /'
elif [ "$rc" -eq 1 ]; then
  echo ">> hashcat exhausted the wordlist without cracking everything."
  echo ">> Try a larger list (wordlists-setup.sh --large) or a rules pass (--rules best64)."
fi
exit "$rc"

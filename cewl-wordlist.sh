#!/usr/bin/env bash
#
# cewl-wordlist.sh
#
# Build a target-specific wordlist. Scrapes the site with cewl, optionally folds
# in a names list, then expands everything with a hashcat rules pass (or a small
# built-in season/year/suffix mutation if hashcat isn't available). Output feeds
# spray.sh and crack.sh.
#
# Usage:
#   ./cewl-wordlist.sh https://example.com -o custom.txt
#   ./cewl-wordlist.sh https://example.com --depth 2 --min 5 --rules best64
#   ./cewl-wordlist.sh https://example.com --names employees.txt
#
set -uo pipefail

OUT="custom-wordlist.txt"
DEPTH=2
MINLEN=4
RULES=""
NAMES=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

resolve_rules() {
  local r="$1"
  [ -f "$r" ] && { echo "$r"; return 0; }
  for d in /usr/share/hashcat/rules /usr/share/doc/hashcat/rules; do
    [ -f "$d/${r}.rule" ] && { echo "$d/${r}.rule"; return 0; }
  done
  return 1
}

URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    -o|--out)  shift; [ $# -gt 0 ] || die "-o needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    --depth)   shift; DEPTH="$1" ;;
    --min)     shift; MINLEN="$1" ;;
    --rules)   shift; RULES="$1" ;;
    --names)   shift; NAMES="$1" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$URL" ] || die "Only one URL."; URL="$1" ;;
  esac
  shift
done
[ -n "$URL" ] || { echo "No URL given." >&2; usage 2; }
have cewl || die "cewl not found (apt install cewl)."

tmp=$(mktemp -d)
base="$tmp/base.txt"

echo ">> Scraping $URL with cewl (depth $DEPTH, min length $MINLEN)..."
cewl -d "$DEPTH" -m "$MINLEN" "$URL" 2>/dev/null | sed '/^$/d' | sort -u > "$base" || true
echo ">> cewl words: $(grep -c '' "$base" 2>/dev/null || true)"

if [ -n "$NAMES" ] && [ -f "$NAMES" ]; then
  # Add raw names and simple first.last -> flast style handles.
  cat "$NAMES" >> "$base"
  awk '{print tolower($0)}' "$NAMES" | sort -u >> "$base"
fi
sort -u "$base" -o "$base"

# --- expand with mutations ------------------------------------------------
if [ -n "$RULES" ] && have hashcat; then
  rpath=$(resolve_rules "$RULES") || die "Rules file not found: $RULES"
  echo ">> Expanding with hashcat rules: $rpath"
  hashcat --stdout "$base" -r "$rpath" 2>/dev/null | sort -u > "$OUT"
else
  [ -n "$RULES" ] && echo ">> hashcat not available; using built-in mutation instead."
  echo ">> Applying built-in season/year/suffix mutation..."
  {
    cat "$base"
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      cap=$(printf '%s' "$w" | sed 's/^\(.\)/\U\1/')
      for suf in 1 12 123 ! @ 2024 2025 '!' '2025!'; do
        printf '%s%s\n%s%s\n' "$w" "$suf" "$cap" "$suf"
      done
    done < "$base"
  } | sort -u > "$OUT"
fi

echo
echo "================ SUMMARY ================"
echo "Wordlist : $OUT ($(grep -c '' "$OUT" 2>/dev/null || true) entries)"
echo "Use with : spray.sh <dc> -d <dom> -U users.txt -P $OUT"
echo "           crack.sh hashes.txt --wordlist $OUT"
echo "========================================"
rm -rf "$tmp"

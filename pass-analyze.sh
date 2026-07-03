#!/usr/bin/env bash
#
# pass-analyze.sh
#
# Stats on a list of cracked passwords to guide the next cracking pass: length
# distribution, most common base words, character-set makeup, and top hashcat
# masks. Think of it as a small pipal.
#
# Usage:
#   ./pass-analyze.sh cracked.txt
#   ./pass-analyze.sh cracked.txt --top 20
#   hashcat -m 1000 hashes --show | cut -d: -f2 | ./pass-analyze.sh -
#
set -uo pipefail

TOP=10
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --top)     shift; [ $# -gt 0 ] || die "--top needs a number"; TOP="$1" ;;
    --top=*)   TOP="${1#*=}" ;;
    -)         INPUT="-" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$INPUT" ] || die "Only one input."; INPUT="$1" ;;
  esac
  shift
done
[ -n "$INPUT" ] || { echo "No input file given (use - for stdin)." >&2; usage 2; }

SRC=$(mktemp)
if [ "$INPUT" = "-" ]; then cat > "$SRC"; else [ -f "$INPUT" ] || die "File not found: $INPUT"; cat "$INPUT" > "$SRC"; fi
# Drop blank lines.
sed -i '/^$/d' "$SRC" 2>/dev/null || true
total=$(grep -c '' "$SRC")
[ "$total" -gt 0 ] || die "No passwords to analyze."

echo "======================================"
echo " Password analysis ($total passwords)"
echo "======================================"

echo
echo "## Length distribution"
awk '{ print length }' "$SRC" | sort -n | uniq -c | \
  awk -v t="$total" '{ printf "   %2s chars : %5d  (%4.1f%%)\n", $2, $1, 100*$1/t }'

echo
echo "## Top $TOP full passwords"
sort "$SRC" | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "   %5d  %s\n",$1,$2}'

echo
echo "## Top $TOP base words (letters only, lowercased, stripped of digits/symbols)"
tr '[:upper:]' '[:lower:]' < "$SRC" | sed -E 's/[^a-z]//g' | sed '/^$/d' \
  | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "   %5d  %s\n",$1,$2}'

echo
echo "## Character-set composition"
awk '
  { c++
    if ($0 ~ /[a-z]/) l++
    if ($0 ~ /[A-Z]/) u++
    if ($0 ~ /[0-9]/) d++
    if ($0 ~ /[^a-zA-Z0-9]/) s++
    if ($0 ~ /^[a-z]+$/) lo++
    if ($0 ~ /^[a-zA-Z]+[0-9]+$/) wd++
  }
  END{
    printf "   contains lowercase : %d (%.1f%%)\n", l, 100*l/c
    printf "   contains uppercase : %d (%.1f%%)\n", u, 100*u/c
    printf "   contains digits    : %d (%.1f%%)\n", d, 100*d/c
    printf "   contains symbols   : %d (%.1f%%)\n", s, 100*s/c
    printf "   all-lowercase      : %d (%.1f%%)\n", lo, 100*lo/c
    printf "   word+digits (e.g. Summer2025) : %d (%.1f%%)\n", wd, 100*wd/c
  }' "$SRC"

echo
echo "## Top $TOP hashcat masks"
awk '{
  m=""
  n=split($0,ch,"")
  for(i=1;i<=n;i++){
    c=ch[i]
    if(c ~ /[a-z]/) m=m"?l"
    else if(c ~ /[A-Z]/) m=m"?u"
    else if(c ~ /[0-9]/) m=m"?d"
    else m=m"?s"
  }
  print m
}' "$SRC" | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "   %5d  %s\n",$1,$2}'

rm -f "$SRC"
echo
echo "Use the top masks with: hashcat -a 3 hashes '<mask>'"

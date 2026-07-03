#!/usr/bin/env bash
#
# evidence.sh
#
# File a screenshot or output file as engagement evidence: copy it into
# report/evidence/ with a timestamped, sequential name and a caption, and keep an
# index.md so figures are ready to drop into the report.
#
# Usage:
#   ./evidence.sh shot.png "admin panel with default creds"
#   ./evidence.sh --workspace ~/eng/acme nmap.txt "full port scan"
#   ./evidence.sh --list
#
set -uo pipefail

WS="."
LIST=0

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    --workspace|-w) shift; [ $# -gt 0 ] || die "--workspace needs a path"; WS="$1" ;;
    --workspace=*) WS="${1#*=}" ;;
    --list)        LIST=1 ;;
    -*)            die "Unknown option: $1 (try --help)" ;;
    *)             ARGS+=("$1") ;;
  esac
  shift
done

EVID="$WS/report/evidence"
INDEX="$EVID/index.md"

if [ "$LIST" -eq 1 ]; then
  [ -f "$INDEX" ] || die "No evidence index at $INDEX yet."
  cat "$INDEX"; exit 0
fi

[ "${#ARGS[@]}" -ge 1 ] || { echo "Give a file (and optional caption)." >&2; usage 2; }
SRC="${ARGS[0]}"
CAPTION="${ARGS[*]:1}"
[ -f "$SRC" ] || die "File not found: $SRC"

mkdir -p "$EVID"
[ -f "$INDEX" ] || printf '# Evidence\n\n' > "$INDEX"

# Sequence number = existing entries + 1.
seq=$(grep -c '^## ' "$INDEX" 2>/dev/null || true)
seq=$((seq+1))
num=$(printf '%03d' "$seq")
ext="${SRC##*.}"; [ "$ext" = "$SRC" ] && ext="dat"
stamp=$(date '+%Y%m%d-%H%M%S')
base="ev${num}_${stamp}.${ext}"
cp "$SRC" "$EVID/$base"

{
  echo "## Figure $seq: ${CAPTION:-untitled}"
  echo "_captured $(date '+%Y-%m-%d %H:%M:%S') from \`$SRC\`_"
  echo
  case "$ext" in
    png|jpg|jpeg|gif|webp) echo "![Figure $seq]($base)" ;;
    *) echo '```'; head -n 40 "$EVID/$base"; echo '```' ;;
  esac
  echo
} >> "$INDEX"

echo ">> Filed as $EVID/$base (figure $seq)"
echo ">> Index: $INDEX"

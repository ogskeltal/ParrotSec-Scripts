#!/usr/bin/env bash
#
# screenshot-web.sh
#
# Screenshot a list of web hosts into a folder, using whichever tool is present
# (eyewitness, gowitness, aquatone) and falling back to headless Chromium with a
# generated HTML gallery. Pairs with subdomain-enum.sh output.
#
# Usage:
#   ./screenshot-web.sh urls.txt
#   ./screenshot-web.sh live-hosts.txt --out ~/engagements/acme/shots
#   ./screenshot-web.sh urls.txt --dry-run
#
# The input is one URL or host per line. Bare hosts are tried over http.
#
set -uo pipefail

OUT=""
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

# Find a Chromium/Chrome binary for the fallback path.
find_chrome() {
  local b
  for b in chromium chromium-browser google-chrome google-chrome-stable chrome; do
    have "$b" && { echo "$b"; return 0; }
  done
  return 1
}

# --- parse args -----------------------------------------------------------
LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --out|-o)     shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)      OUT="${1#*=}" ;;
    -*)           die "Unknown option: $1 (try --help)" ;;
    *)            [ -z "$LIST" ] || die "Only one input file allowed."; LIST="$1" ;;
  esac
  shift
done
[ -n "$LIST" ] || { echo "No input file given." >&2; usage 2; }
[ -f "$LIST" ] || die "Input file not found: $LIST"

[ -n "$OUT" ] || OUT="./shots_$(date +%Y-%m-%d)"
run mkdir -p "$OUT"
echo ">> Input  : $LIST ($(wc -l < "$LIST" | tr -d ' ') lines)"
echo ">> Output : $OUT"

# --- prefer a purpose-built tool ------------------------------------------
if have eyewitness; then
  echo ">> Using EyeWitness..."
  run eyewitness --web -f "$LIST" -d "$OUT" --no-prompt
  echo ">> Done. Open $OUT/report.html"
  exit 0
fi

if have gowitness; then
  echo ">> Using gowitness..."
  # gowitness CLI changed across versions; try v3 then the older form.
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "   [dry-run] gowitness scan file -f $LIST --screenshot-path $OUT"
  elif gowitness scan file -f "$LIST" --screenshot-path "$OUT" 2>/dev/null; then
    :
  else
    gowitness file -f "$LIST" -P "$OUT" || die "gowitness failed; check its version/syntax."
  fi
  echo ">> Done. See $OUT (gowitness report / DB)."
  exit 0
fi

if have aquatone; then
  echo ">> Using aquatone..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "   [dry-run] cat $LIST | aquatone -out $OUT"
  else
    aquatone -out "$OUT" < "$LIST"
  fi
  echo ">> Done. Open $OUT/aquatone_report.html"
  exit 0
fi

# --- fallback: headless Chromium ------------------------------------------
if ! CHROME=$(find_chrome); then
  if [ "$DRY_RUN" -eq 1 ]; then
    CHROME="chromium"   # placeholder so --dry-run can still preview the plan
  else
    die "No screenshot tool found (eyewitness/gowitness/aquatone) and no Chromium for the fallback."
  fi
fi
echo ">> No dedicated tool found; using headless $CHROME."

index="$OUT/index.html"
[ "$DRY_RUN" -eq 1 ] || printf '<!doctype html><meta charset=utf-8><title>screenshots</title><body style="font-family:sans-serif">\n' > "$index"

n=0
while IFS= read -r line; do
  line="${line%%[[:space:]]*}"
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac
  # add a scheme if the line is a bare host
  case "$line" in http://*|https://*) url="$line" ;; *) url="http://$line" ;; esac
  # safe filename from the url
  fname=$(printf '%s' "$url" | tr -c 'a-zA-Z0-9' '_')
  png="$OUT/${fname}.png"
  echo "   -> $url"
  run "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
      --window-size=1440,900 --screenshot="$png" "$url"
  if [ "$DRY_RUN" -ne 1 ] && [ -f "$png" ]; then
    printf '<div><p>%s</p><img src="%s" style="max-width:100%%;border:1px solid #ccc"></div><hr>\n' \
      "$url" "$(basename "$png")" >> "$index"
    n=$((n+1))
  fi
done < "$LIST"

echo
echo "================ SUMMARY ================"
echo "Screenshots : $n"
echo "Gallery     : $index"
echo "========================================"
[ "$DRY_RUN" -eq 1 ] || [ "$n" -gt 0 ] || { echo "Nothing captured; check the URLs and $CHROME."; exit 1; }

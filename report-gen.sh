#!/usr/bin/env bash
#
# report-gen.sh
#
# Stitch a workspace.sh engagement directory into a single Markdown draft:
# scope, running notes, an index of scan/web/loot artifacts, and inline nmap
# output where present. Optionally render to HTML with pandoc. A starting point
# for the write-up, not a finished report.
#
# Usage:
#   ./report-gen.sh ~/engagements/acme_2026-07-03
#   ./report-gen.sh ./acme --out acme-report.md
#   ./report-gen.sh ./acme --html            # also produce report.html (needs pandoc)
#
set -uo pipefail

OUT=""
HTML=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

WS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    --html)    HTML=1 ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$WS" ] || die "Only one workspace allowed."; WS="$1" ;;
  esac
  shift
done
[ -n "$WS" ] || { echo "No workspace directory given." >&2; usage 2; }
[ -d "$WS" ] || die "Not a directory: $WS"

WS="${WS%/}"
name=$(basename "$WS")
[ -n "$OUT" ] || OUT="$WS/report/report.md"
mkdir -p "$(dirname "$OUT")"

# helper: append a file's contents in a fenced block if it exists
embed() { # path language
  [ -f "$1" ] || return 0
  echo; echo "\`\`\`${2:-}"; cat "$1"; echo "\`\`\`"; echo
}
list_dir() { # dir
  [ -d "$1" ] || { echo "_none_"; return 0; }
  local found=0
  while IFS= read -r f; do
    found=1; echo "- \`${f#"$WS"/}\`"
  done < <(find "$1" -type f | sort)
  [ "$found" -eq 1 ] || echo "_none_"
}

{
  echo "# Engagement report: ${name}"
  echo
  echo "_Generated $(date '+%Y-%m-%d %H:%M:%S') from \`$WS\`_"
  echo
  echo "## Scope"
  if [ -f "$WS/scope.txt" ]; then embed "$WS/scope.txt"; else echo "_no scope.txt_"; fi

  echo "## Notes"
  if [ -f "$WS/notes/notes.md" ]; then
    echo; cat "$WS/notes/notes.md"; echo
  elif [ -f "$WS/notes.md" ]; then
    echo; cat "$WS/notes.md"; echo
  else
    echo "_no notes found_"
  fi

  echo "## Scans"
  # Inline the primary nmap output if present, else list the dir.
  nmap_txt=$(find "$WS/scans" -maxdepth 2 -name '*.nmap' 2>/dev/null | head -n1 || true)
  if [ -n "$nmap_txt" ]; then
    echo; echo "### nmap (\`${nmap_txt#"$WS"/}\`)"
    embed "$nmap_txt"
  fi
  echo "### Scan artifacts"
  list_dir "$WS/scans"
  echo

  echo "## Web"
  list_dir "$WS/web"
  echo

  echo "## Loot"
  list_dir "$WS/loot"
  echo

  echo "## Findings"
  echo
  echo "| # | Severity | Title | Host | Notes |"
  echo "| - | -------- | ----- | ---- | ----- |"
  echo "| 1 |          |       |      |       |"
  echo
  echo "_Fill in from the notes and scan output above._"
} > "$OUT"

echo ">> Markdown report: $OUT"

if [ "$HTML" -eq 1 ]; then
  html="${OUT%.md}.html"
  if have pandoc; then
    pandoc -s "$OUT" -o "$html" && echo ">> HTML report: $html"
  else
    echo ">> pandoc not installed; skipping HTML. (apt install pandoc)"
  fi
fi

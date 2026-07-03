#!/usr/bin/env bash
#
# linpeas-fetch.sh
#
# Download the current privilege-escalation enumeration binaries (linpeas,
# winpeas, pspy) into a directory, so what you serve to a target is always the
# latest release. Optionally start an HTTP server to hand them over.
#
# Usage:
#   ./linpeas-fetch.sh                    # into ./privesc-tools
#   ./linpeas-fetch.sh --dir ~/tools
#   ./linpeas-fetch.sh --serve            # download, then http.server on 8000
#   ./linpeas-fetch.sh --dry-run
#
set -uo pipefail

DIR="./privesc-tools"
SERVE=0
PORT=8000
DRY_RUN=0

PEAS="https://github.com/carlospolop/PEASS-ng/releases/latest/download"
PSPY="https://github.com/DominicBreuker/pspy/releases/latest/download"

# filename|base-url|executable
ASSETS=(
  "linpeas.sh|$PEAS|1"
  "linpeas_small.sh|$PEAS|1"
  "winPEASx64.exe|$PEAS|0"
  "winPEASx86.exe|$PEAS|0"
  "winPEAS.bat|$PEAS|0"
  "pspy64|$PSPY|1"
  "pspy32|$PSPY|1"
)

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
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --serve)      SERVE=1 ;;
    --dir)        shift; [ $# -gt 0 ] || die "--dir needs a path"; DIR="$1" ;;
    --dir=*)      DIR="${1#*=}" ;;
    --port)       shift; [ $# -gt 0 ] || die "--port needs a value"; PORT="$1" ;;
    --port=*)     PORT="${1#*=}" ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

have curl || have wget || die "Need curl or wget to download."
run mkdir -p "$DIR"
echo ">> Fetching privesc tools into $DIR"

fetch() { # url dest
  if have curl; then run curl -fsSL "$1" -o "$2"; else run wget -q "$1" -O "$2"; fi
}

ok=0; failed=()
for entry in "${ASSETS[@]}"; do
  IFS='|' read -r name base exe <<< "$entry"
  url="$base/$name"
  dest="$DIR/$name"
  echo "   -> $name"
  if fetch "$url" "$dest"; then
    # A failed download can still leave a 0-byte or HTML file; sanity-check size.
    if [ "$DRY_RUN" -ne 1 ] && [ ! -s "$dest" ]; then
      failed+=("$name"); rm -f "$dest"; continue
    fi
    [ "$exe" = "1" ] && run chmod +x "$dest"
    ok=$((ok+1))
  else
    failed+=("$name")
  fi
done

echo
echo "================ SUMMARY ================"
echo "Directory : $DIR"
echo "Fetched   : $ok / ${#ASSETS[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "Failed    : ${#failed[@]}"
  printf '   %s\n' "${failed[@]}"
fi
echo "========================================"

if [ "$SERVE" -eq 1 ]; then
  have python3 || die "python3 not found for --serve."
  echo ">> Serving $DIR on port $PORT (Ctrl-C to stop)..."
  [ "$DRY_RUN" -eq 1 ] && { echo "   [dry-run] python3 -m http.server $PORT --directory $DIR"; exit 0; }
  exec python3 -m http.server "$PORT" --directory "$DIR"
fi

[ "${#failed[@]}" -eq 0 ] || exit 1
exit 0

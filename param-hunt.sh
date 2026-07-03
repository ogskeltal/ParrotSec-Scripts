#!/usr/bin/env bash
#
# param-hunt.sh
#
# Discover URL parameters for a target using whichever of gau, waybackurls,
# paramspider, and arjun are installed, merge them, and optionally run a light
# nuclei pass over the collected URLs. Skips tools that aren't present.
#
# Usage:
#   ./param-hunt.sh https://example.com
#   ./param-hunt.sh example.com --out ./params
#   ./param-hunt.sh example.com --nuclei
#
set -uo pipefail

OUT=""
RUN_NUCLEI=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    --nuclei)  RUN_NUCLEI=1 ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$TARGET" ] || die "Only one target."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target given." >&2; usage 2; }

host="${TARGET#*://}"; host="${host%%/*}"
slug=$(printf '%s' "$host" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./params_${slug}"
mkdir -p "$OUT"

if ! have gau && ! have waybackurls && ! have paramspider && ! have arjun; then
  die "None of gau/waybackurls/paramspider/arjun are installed. Install at least one."
fi

raw="$OUT/.raw"; : > "$raw"

if have gau; then
  echo ">> gau..."
  gau "$host" 2>/dev/null >> "$raw" || true
fi
if have waybackurls; then
  echo ">> waybackurls..."
  echo "$host" | waybackurls 2>/dev/null >> "$raw" || true
fi
if have paramspider; then
  echo ">> paramspider..."
  paramspider -d "$host" 2>/dev/null | grep -oE 'https?://[^ ]+' >> "$raw" || true
fi

# Keep only URLs that actually carry a query parameter.
grep -E '\?[^=]+=' "$raw" 2>/dev/null | sort -u > "$OUT/urls-with-params.txt" || true
# Extract just the parameter names.
grep -oE '[?&][A-Za-z0-9_]+=' "$OUT/urls-with-params.txt" 2>/dev/null \
  | tr -d '?&=' | sort -u > "$OUT/param-names.txt" || true

# arjun actively finds params on a single URL.
if have arjun; then
  echo ">> arjun (active param discovery)..."
  url="$TARGET"; case "$url" in http*://*) ;; *) url="https://$host" ;; esac
  arjun -u "$url" -oT "$OUT/arjun.txt" >/dev/null 2>&1 || true
fi

rm -f "$raw"
urls=$(grep -c '' "$OUT/urls-with-params.txt" 2>/dev/null || true)
names=$(grep -c '' "$OUT/param-names.txt" 2>/dev/null || true)
echo ">> URLs with params: $urls   distinct param names: $names"

if [ "$RUN_NUCLEI" -eq 1 ] && have nuclei && [ "$urls" -gt 0 ]; then
  echo ">> nuclei over collected URLs..."
  nuclei -silent -l "$OUT/urls-with-params.txt" -o "$OUT/nuclei.txt" || true
fi

echo
echo "================ SUMMARY ================"
echo "Output       : $OUT/"
echo "  urls-with-params.txt ($urls)"
echo "  param-names.txt ($names)"
[ -f "$OUT/arjun.txt" ] && echo "  arjun.txt"
echo "Next: feed urls-with-params.txt to sqlmap -m or your fuzzer of choice."
echo "========================================"

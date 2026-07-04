#!/usr/bin/env bash
#
# cloud-enum.sh
#
# Probe for public cloud storage tied to a keyword: AWS S3 buckets, Azure blob
# containers, and Google Cloud Storage. Generates candidate names from the
# keyword with common affixes and reports which exist and which are readable.
# Only run this against an organization you are authorized to assess.
#
# Usage:
#   ./cloud-enum.sh acme
#   ./cloud-enum.sh acme --out ./cloud
#   ./cloud-enum.sh acme --affixes affixes.txt
#
set -uo pipefail

OUT=""
AFFIX_FILE=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

DEFAULT_AFFIXES=(
  "" "-dev" "-prod" "-stage" "-staging" "-test" "-qa" "-backup" "-backups"
  "-data" "-assets" "-media" "-static" "-public" "-private" "-internal"
  "-files" "-uploads" "-logs" "-db" "-images" "-web" "-www" "-cdn" "-app"
)

KEYWORD=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage 0 ;;
    --out|-o)   shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)    OUT="${1#*=}" ;;
    --affixes)  shift; AFFIX_FILE="$1" ;;
    -*)         die "Unknown option: $1 (try --help)" ;;
    *)          [ -z "$KEYWORD" ] || die "Only one keyword."; KEYWORD="$1" ;;
  esac
  shift
done
[ -n "$KEYWORD" ] || { echo "No keyword given." >&2; usage 2; }
have curl || die "curl not found."

# Prefer a dedicated tool if it's installed.
if have cloud_enum; then
  echo ">> cloud_enum found; running it (fuller coverage)..."
  args=(-k "$KEYWORD"); [ -n "$OUT" ] && { mkdir -p "$OUT"; args+=(-l "$OUT/cloud_enum.txt"); }
  exec cloud_enum "${args[@]}"
fi

# Build the candidate list.
affixes=("${DEFAULT_AFFIXES[@]}")
if [ -n "$AFFIX_FILE" ] && [ -f "$AFFIX_FILE" ]; then
  mapfile -t affixes < "$AFFIX_FILE"
fi
names=()
for a in "${affixes[@]}"; do
  names+=("${KEYWORD}${a}")
  # also prefix form (dev-acme)
  [ -n "$a" ] && names+=("${a#-}-${KEYWORD}")
done

report=""
[ -n "$OUT" ] && { mkdir -p "$OUT"; report="$OUT/cloud-enum.txt"; }
log() { if [ -n "$report" ]; then echo "$*" | tee -a "$report"; else echo "$*"; fi; }

# curl helper returning the HTTP status.
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$1" 2>/dev/null || echo 000; }

log ">> Authorized targets only. Probing ${#names[@]} candidate names..."
found=0
for n in "${names[@]}"; do
  # AWS S3
  c=$(code "https://${n}.s3.amazonaws.com/")
  case "$c" in
    200) log "  [OPEN]   s3: ${n}  (public listing!)"; found=$((found+1)) ;;
    403) log "  [exists] s3: ${n}  (403, private)"; found=$((found+1)) ;;
  esac
  # Azure blob
  c=$(code "https://${n}.blob.core.windows.net/")
  case "$c" in 200|400|403) log "  [exists] azure-blob: ${n}  (HTTP $c)"; found=$((found+1)) ;; esac
  # GCS
  c=$(code "https://storage.googleapis.com/${n}/")
  case "$c" in
    200) log "  [OPEN]   gcs: ${n}  (public listing!)"; found=$((found+1)) ;;
    403) log "  [exists] gcs: ${n}  (403, private)"; found=$((found+1)) ;;
  esac
done

log ""
log "================ SUMMARY ================"
log "candidates probed : ${#names[@]}"
log "hits (exist/open) : $found"
[ -n "$report" ] && log "report            : $report"
log "OPEN entries allow anonymous listing; enumerate those first."
log "========================================"

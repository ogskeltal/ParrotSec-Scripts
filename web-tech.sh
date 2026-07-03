#!/usr/bin/env bash
#
# web-tech.sh
#
# Deep fingerprint of a single web target: HTTP headers, technology detection
# (whatweb / wappalyzer), TLS certificate, and robots.txt / sitemap.xml. Writes
# each section to a report and prints it. Skips steps whose tool is missing.
#
# Usage:
#   ./web-tech.sh https://example.com
#   ./web-tech.sh example.com --out ./example-fingerprint.txt
#
set -uo pipefail

OUT=""
die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$URL" ] || die "Only one URL allowed."; URL="$1" ;;
  esac
  shift
done
[ -n "$URL" ] || { echo "No URL given." >&2; usage 2; }

# Add a scheme if the user passed a bare host.
case "$URL" in http://*|https://*) ;; *) URL="https://$URL" ;; esac
host="${URL#*://}"; host="${host%%/*}"; host="${host%%:*}"
port=443; case "$URL" in http://*) port=80 ;; esac

REPORT=$(mktemp)
section() { echo; echo "===== $* ====="; }

{
  echo "web-tech fingerprint"
  echo "url  : $URL"
  echo "host : $host"
  echo "date : $(date '+%Y-%m-%d %H:%M:%S')"
} >> "$REPORT"

# --- headers --------------------------------------------------------------
{
  section "HTTP headers"
  if have curl; then
    curl -sSIL --max-time 15 "$URL" 2>&1 || echo "(curl failed)"
  else
    echo "curl not installed"
  fi
} >> "$REPORT"

# --- technology detection -------------------------------------------------
{
  section "Technology (whatweb)"
  if have whatweb; then
    whatweb -a3 "$URL" 2>&1 || echo "(whatweb failed)"
  else
    echo "whatweb not installed"
  fi
  if have wappalyzer; then
    section "Technology (wappalyzer)"
    wappalyzer "$URL" 2>&1 || echo "(wappalyzer failed)"
  fi
} >> "$REPORT"

# --- TLS certificate ------------------------------------------------------
{
  section "TLS certificate"
  if [ "$port" = "443" ] && have openssl; then
    echo | timeout 15 openssl s_client -connect "${host}:443" -servername "$host" 2>/dev/null \
      | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null \
      || echo "(no certificate / handshake failed)"
  else
    echo "skipped (http or openssl missing)"
  fi
} >> "$REPORT"

# --- robots / sitemap -----------------------------------------------------
{
  section "robots.txt"
  if have curl; then curl -sS --max-time 10 "${URL%/}/robots.txt" 2>&1 | head -n 40 || echo "(none)"; fi
  section "sitemap.xml"
  if have curl; then curl -sS --max-time 10 "${URL%/}/sitemap.xml" 2>&1 | head -n 20 || echo "(none)"; fi
} >> "$REPORT"

# --- output ---------------------------------------------------------------
if [ -n "$OUT" ]; then cp "$REPORT" "$OUT"; echo ">> Report written to $OUT"; fi
cat "$REPORT"
rm -f "$REPORT"

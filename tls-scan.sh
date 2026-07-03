#!/usr/bin/env bash
#
# tls-scan.sh
#
# Grade a host's TLS: protocols, ciphers, certificate details and expiry, and a
# few well-known issues. Uses testssl.sh or sslscan when present, otherwise a
# focused openssl fallback that still catches the important things.
#
# Usage:
#   ./tls-scan.sh example.com
#   ./tls-scan.sh example.com:8443 --out ./tls
#
set -uo pipefail

OUT=""
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
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$TARGET" ] || die "Only one target."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No host[:port] given." >&2; usage 2; }

host="${TARGET%%:*}"
port="${TARGET##*:}"; [ "$port" = "$TARGET" ] && port=443

report=""
[ -n "$OUT" ] && { mkdir -p "$OUT"; report="$OUT/tls_${host}_${port}.txt"; }
sink() { if [ -n "$report" ]; then tee -a "$report"; else cat; fi; }

echo ">> TLS scan: ${host}:${port}" | sink

# --- preferred tools ------------------------------------------------------
if have testssl.sh || have testssl; then
  T=$(command -v testssl.sh || command -v testssl)
  echo ">> Using $T ..." | sink
  "$T" --quiet --color 0 "${host}:${port}" | sink
  exit 0
fi

if have sslscan; then
  echo ">> Using sslscan ..." | sink
  sslscan --no-colour "${host}:${port}" | sink
  exit 0
fi

# --- openssl fallback -----------------------------------------------------
have openssl || die "Need testssl.sh, sslscan, or openssl."
echo ">> No testssl/sslscan; using openssl fallback." | sink

{
  echo
  echo "===== protocols ====="
  for proto in ssl3 tls1 tls1_1 tls1_2 tls1_3; do
    if echo | timeout 8 openssl s_client -connect "${host}:${port}" -"$proto" 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
      state="ENABLED"
      case "$proto" in ssl3|tls1|tls1_1) state="ENABLED  [!] deprecated" ;; esac
      printf '   %-8s %s\n' "$proto" "$state"
    else
      printf '   %-8s disabled/failed\n' "$proto"
    fi
  done

  echo
  echo "===== certificate ====="
  echo | timeout 10 openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null \
    || echo "   (handshake failed)"

  echo
  echo "===== notes ====="
  echo "   Deprecated protocols above are findings on their own."
  echo "   For Heartbleed/ROBOT/etc., install testssl.sh for the full check."
} | sink

[ -n "$report" ] && echo ">> Report: $report"

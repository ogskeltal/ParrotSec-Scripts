#!/usr/bin/env bash
#
# jwt-tool.sh
#
# Decode a JSON Web Token, flag common weaknesses, and try to crack the HMAC
# signing key against a wordlist. Self-contained: decoding and the alg checks use
# base64/openssl locally, no external service.
#
# Usage:
#   ./jwt-tool.sh <token>
#   ./jwt-tool.sh <token> --wordlist /usr/share/wordlists/rockyou.txt
#   echo "$TOKEN" | ./jwt-tool.sh -
#
set -uo pipefail

WORDLIST=""
die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# base64url decode (pad and translate to standard base64).
b64url_decode() {
  local s="$1"
  s="${s//-/+}"; s="${s//_//}"
  case $(( ${#s} % 4 )) in 2) s="${s}==" ;; 3) s="${s}=" ;; esac
  printf '%s' "$s" | base64 -d 2>/dev/null
}

TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    -w|--wordlist) shift; [ $# -gt 0 ] || die "-w needs a path"; WORDLIST="$1" ;;
    --wordlist=*)  WORDLIST="${1#*=}" ;;
    -)             TOKEN=$(cat); ;;
    -*)            die "Unknown option: $1 (try --help)" ;;
    *)             [ -z "$TOKEN" ] || die "Only one token."; TOKEN="$1" ;;
  esac
  shift
done
TOKEN="${TOKEN//[[:space:]]/}"
[ -n "$TOKEN" ] || { echo "No token given (use - for stdin)." >&2; usage 2; }

# Split into the three parts.
IFS='.' read -r H P S <<< "$TOKEN"
[ -n "$H" ] && [ -n "$P" ] || die "That doesn't look like a JWT (need header.payload.signature)."

echo "===== header ====="
if have jq; then b64url_decode "$H" | jq . 2>/dev/null || b64url_decode "$H"; else b64url_decode "$H"; echo; fi
echo
echo "===== payload ====="
if have jq; then b64url_decode "$P" | jq . 2>/dev/null || b64url_decode "$P"; else b64url_decode "$P"; echo; fi
echo

hdr=$(b64url_decode "$H")
alg=""
if have jq; then alg=$(printf '%s' "$hdr" | jq -r '.alg' 2>/dev/null); fi
if [ -z "$alg" ] || [ "$alg" = "null" ]; then
  alg=$(printf '%s' "$hdr" | grep -oE '"alg"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
fi
echo "===== checks ====="
echo "   alg: $alg"
case "$alg" in
  none|None|NONE) echo "   [!] alg=none - server may accept an unsigned token. Try stripping the signature." ;;
  HS*)            echo "   [i] HMAC (symmetric) - crackable if the secret is weak (see below)." ;;
  RS*|ES*|PS*)    echo "   [i] asymmetric - check for alg-confusion (RS256->HS256 with the public key as secret)." ;;
esac
# exp check
exp=$(b64url_decode "$P" | grep -oE '"exp"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$exp" ] && echo "   [i] exp claim present: $exp"

# --- crack HMAC secret ----------------------------------------------------
case "$alg" in HS*) ;; *) exit 0 ;; esac
[ -n "$WORDLIST" ] || WORDLIST="/usr/share/wordlists/rockyou.txt"
[ -f "$WORDLIST" ] || { echo; echo ">> No wordlist for the secret crack (pass -w). Skipping."; exit 0; }
have openssl || { echo ">> openssl needed for the secret crack; skipping."; exit 0; }

echo
echo ">> Trying to crack the HS* secret with $(basename "$WORDLIST")..."
signing_input="${H}.${P}"
want="$S"
found=""
while IFS= read -r secret; do
  [ -n "$secret" ] || continue
  sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null \
        | base64 | tr '+/' '-_' | tr -d '=')
  if [ "$sig" = "$want" ]; then found="$secret"; break; fi
done < "$WORDLIST"

if [ -n "$found" ]; then
  echo ">> [+] SECRET FOUND: $found"
  echo ">> You can now forge tokens with this key."
else
  echo ">> secret not found in this list (only HS256 is checked here)."
fi

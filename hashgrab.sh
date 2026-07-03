#!/usr/bin/env bash
#
# hashgrab.sh
#
# Pull hashes out of common dump formats and sort them into per-type files that
# crack.sh / hashcat can use directly. Reads a file or stdin. Prints the hashcat
# mode for each type it writes.
#
# Recognizes:
#   - NTLM from impacket secretsdump (user:rid:lm:nt:::)   -> ntlm.txt      (-m 1000)
#   - NetNTLMv2 (user::domain:...:...)                     -> netntlmv2.txt (-m 5600)
#   - Kerberos AS-REP / TGS ($krb5asrep$, $krb5tgs$)       -> krb5*.txt     (-m 18200/13100)
#   - /etc/shadow crypt hashes ($1/$5/$6/$2/$y)            -> per-scheme    (varies)
#
# Usage:
#   ./hashgrab.sh secretsdump.txt
#   secretsdump.py ... | ./hashgrab.sh -
#   ./hashgrab.sh shadow.txt --out ./hashes
#
set -uo pipefail

OUT="."
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -)         INPUT="-" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$INPUT" ] || die "Only one input allowed."; INPUT="$1" ;;
  esac
  shift
done
[ -n "$INPUT" ] || { echo "No input file given (use - for stdin)." >&2; usage 2; }

mkdir -p "$OUT" || die "Cannot create $OUT"

# Read all input once into a temp file so we can scan it repeatedly.
SRC=$(mktemp)
if [ "$INPUT" = "-" ]; then cat > "$SRC"; else [ -f "$INPUT" ] || die "File not found: $INPUT"; cat "$INPUT" > "$SRC"; fi

wrote=()
report() { # file mode label count
  echo "   $4: $3 -> $1  (hashcat -m $2)"
  wrote+=("$1|$2")
}

# --- NTLM from secretsdump: user:rid:lmhash:nthash::: ---------------------
# Grab the 4th colon field when it is 32 hex chars.
ntlm=$(awk -F: 'NF>=4 && $4 ~ /^[0-9a-fA-F]{32}$/ {print $4}' "$SRC" | sort -u)
if [ -n "$ntlm" ]; then
  echo "$ntlm" > "$OUT/ntlm.txt"
  report "$OUT/ntlm.txt" 1000 "$(echo "$ntlm" | wc -l | tr -d ' ') hashes" "NTLM"
fi

# --- NetNTLMv2: user::domain:challenge:response:... -----------------------
netv2=$(grep -E '^[^:]+::[^:]+:[0-9a-fA-F]+:[0-9a-fA-F]+:' "$SRC" | sort -u)
if [ -n "$netv2" ]; then
  echo "$netv2" > "$OUT/netntlmv2.txt"
  report "$OUT/netntlmv2.txt" 5600 "$(echo "$netv2" | wc -l | tr -d ' ') hashes" "NetNTLMv2"
fi

# --- Kerberos -------------------------------------------------------------
asrep=$(grep -E '\$krb5asrep\$' "$SRC" | sort -u)
if [ -n "$asrep" ]; then
  echo "$asrep" > "$OUT/krb5asrep.txt"
  report "$OUT/krb5asrep.txt" 18200 "$(echo "$asrep" | wc -l | tr -d ' ') hashes" "Kerberos AS-REP"
fi
tgs=$(grep -E '\$krb5tgs\$' "$SRC" | sort -u)
if [ -n "$tgs" ]; then
  echo "$tgs" > "$OUT/krb5tgs.txt"
  report "$OUT/krb5tgs.txt" 13100 "$(echo "$tgs" | wc -l | tr -d ' ') hashes" "Kerberos TGS"
fi

# --- Unix crypt from shadow: keep user:$scheme$... ------------------------
declare -A SCHEME_MODE=( [1]=500 [5]=7400 [6]=1800 [y]=3200 )
declare -A SCHEME_NAME=( [1]="md5crypt" [5]="sha256crypt" [6]="sha512crypt" [y]="yescrypt/bcrypt" )
for s in 1 5 6 y; do
  rows=$(grep -E "^[^:]+:\\\$${s}\\\$" "$SRC" | sort -u || true)
  if [ -n "$rows" ]; then
    f="$OUT/unix_${SCHEME_NAME[$s]%%/*}.txt"
    echo "$rows" > "$f"
    report "$f" "${SCHEME_MODE[$s]}" "$(echo "$rows" | wc -l | tr -d ' ') hashes" "${SCHEME_NAME[$s]}"
  fi
done
# bcrypt written as $2a/$2b/$2y
bcrypt=$(grep -E "^[^:]+:\\\$2[aby]\\\$" "$SRC" | sort -u || true)
if [ -n "$bcrypt" ]; then
  echo "$bcrypt" > "$OUT/unix_bcrypt.txt"
  report "$OUT/unix_bcrypt.txt" 3200 "$(echo "$bcrypt" | wc -l | tr -d ' ') hashes" "bcrypt"
fi

rm -f "$SRC"

echo
echo "================ SUMMARY ================"
if [ "${#wrote[@]}" -eq 0 ]; then
  echo "No recognized hashes found."
  echo "========================================"
  exit 1
fi
echo "Wrote ${#wrote[@]} file(s) to $OUT:"
for w in "${wrote[@]}"; do
  echo "   ${w%%|*}   (crack.sh ${w%%|*} --type ${w#*|})"
done
echo "========================================"
exit 0

#!/usr/bin/env bash
#
# loot-parser.sh
#
# Sweep a directory for secrets: private keys, cloud credentials, tokens,
# connection strings, and password-like assignments, plus interesting file
# names. Read-only. Writes a findings report. Meant for triaging an engagement's
# loot/ directory, not as a definitive secret scanner.
#
# Usage:
#   ./loot-parser.sh ~/engagements/acme/loot
#   ./loot-parser.sh ./loot --out findings.txt
#   ./loot-parser.sh ./loot --quiet          # report to file only
#
set -uo pipefail

OUT=""
QUIET=0

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# name|regex  (extended regex, case-sensitive unless noted in the name)
PATTERNS=(
  "Private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "AWS access key id|AKIA[0-9A-Z]{16}"
  "AWS secret (heuristic)|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}"
  "Google API key|AIza[0-9A-Za-z_-]{35}"
  "Slack token|xox[baprs]-[0-9A-Za-z-]{10,}"
  "GitHub token|gh[posru]_[0-9A-Za-z]{36}"
  "JWT|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"
  "DB connection string|(mysql|postgres|postgresql|mongodb(\\+srv)?|redis|amqp)://[^[:space:]\"']+"
  "Password assignment|(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*[^[:space:]\"']{4,}"
  "Generic secret/apikey|(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*[^[:space:]\"']{8,}"
  "Authorization header|Authorization:[[:space:]]*(Basic|Bearer)[[:space:]]+[A-Za-z0-9._+/=-]{8,}"
)

# Interesting file names (basename globs).
NAME_HINTS=(
  "id_rsa" "id_dsa" "id_ecdsa" "id_ed25519" "*.pem" "*.ppk" "*.pfx" "*.p12"
  "*.kdbx" "*.ovpn" ".env" "*.env" "wp-config.php" "web.config"
  "settings.py" "credentials" "*.kirbi" "*.ntds" "SAM" "SYSTEM" "shadow"
  "*.pcap" "*.pcapng" ".npmrc" ".git-credentials" ".htpasswd"
)

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --quiet|-q) QUIET=1 ;;
    --out) OUT="__next__" ;;
    --out=*) OUT="${arg#*=}" ;;
    *)
      if [ "$OUT" = "__next__" ]; then OUT="$arg";
      elif [ -z "${DIR:-}" ]; then DIR="$arg";
      else die "Unexpected argument: $arg"; fi ;;
  esac
done
[ "${OUT:-}" != "__next__" ] || die "--out needs a path"
[ -n "${DIR:-}" ] || { echo "No directory given." >&2; usage 2; }
[ -d "$DIR" ] || die "Not a directory: $DIR"

REPORT=$(mktemp)
{
  echo "loot-parser findings"
  echo "target: $DIR"
  echo "======================================"
} >> "$REPORT"

# --- content matches ------------------------------------------------------
content_hits=0
for entry in "${PATTERNS[@]}"; do
  name="${entry%%|*}"; regex="${entry#*|}"
  # -I skips binaries, -r recurses, -n line numbers.
  # -e is required: several patterns start with '-' and would look like flags.
  matches=$(grep -rInE -e "$regex" "$DIR" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    {
      echo
      echo "## $name"
      # Trim very long lines so the report stays readable.
      echo "$matches" | cut -c1-200
    } >> "$REPORT"
    c=$(echo "$matches" | grep -c '' )
    content_hits=$((content_hits+c))
  fi
done

# --- filename matches -----------------------------------------------------
name_args=()
for h in "${NAME_HINTS[@]}"; do name_args+=(-iname "$h" -o); done
unset 'name_args[${#name_args[@]}-1]'   # drop trailing -o
files=$(find "$DIR" -type f \( "${name_args[@]}" \) 2>/dev/null | sort -u || true)
name_hits=0
if [ -n "$files" ]; then
  {
    echo
    echo "## Interesting file names"
    echo "$files"
  } >> "$REPORT"
  name_hits=$(echo "$files" | grep -c '')
fi

{
  echo
  echo "======================================"
  echo "content matches : $content_hits"
  echo "flagged files   : $name_hits"
} >> "$REPORT"

# --- output ---------------------------------------------------------------
if [ -n "$OUT" ]; then
  cp "$REPORT" "$OUT"
  echo ">> Report written to $OUT"
fi
if [ "$QUIET" -ne 1 ]; then
  cat "$REPORT"
fi
rm -f "$REPORT"

# Exit 0 always; findings are informational. Use grep on the report to gate.
[ $((content_hits + name_hits)) -gt 0 ] && echo ">> Review matches by hand; regex hits include false positives."
exit 0

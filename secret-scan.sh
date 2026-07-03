#!/usr/bin/env bash
#
# secret-scan.sh
#
# Scan looted source for secrets with trufflehog or gitleaks, including full git
# history when the target is a repo. Deeper than loot-parser.sh's flat regex
# sweep, which only sees the current file contents.
#
# Usage:
#   ./secret-scan.sh /path/to/repo
#   ./secret-scan.sh /path/to/dir --out findings.json
#   ./secret-scan.sh https://github.com/org/repo      # trufflehog can scan remote
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
[ -n "$TARGET" ] || { echo "No target (dir/repo/url) given." >&2; usage 2; }

is_url=0
case "$TARGET" in http://*|https://*|git@*) is_url=1 ;; esac
if [ "$is_url" -eq 0 ]; then [ -e "$TARGET" ] || die "Path not found: $TARGET"; fi

is_git=0
[ -d "$TARGET/.git" ] && is_git=1

if ! have trufflehog && ! have gitleaks; then
  die "Neither trufflehog nor gitleaks is installed. Install one (both are on GitHub releases)."
fi

echo ">> Target: $TARGET   (git repo: $([ "$is_git" -eq 1 ] && echo yes || echo no))"

# --- trufflehog -----------------------------------------------------------
if have trufflehog; then
  echo ">> trufflehog..."
  if [ "$is_url" -eq 1 ]; then
    trufflehog git "$TARGET" --results=verified,unknown ${OUT:+--json} \
      ${OUT:+> "$OUT"} || echo "   (trufflehog exited non-zero)"
  elif [ "$is_git" -eq 1 ]; then
    trufflehog git "file://$TARGET" ${OUT:+--json} ${OUT:+> "$OUT"} || true
  else
    trufflehog filesystem "$TARGET" ${OUT:+--json} ${OUT:+> "$OUT"} || true
  fi
  [ -n "$OUT" ] && echo ">> trufflehog output: $OUT"
  exit 0
fi

# --- gitleaks fallback ----------------------------------------------------
echo ">> gitleaks..."
report="${OUT:-./gitleaks-report.json}"
if [ "$is_git" -eq 1 ]; then
  gitleaks detect --source "$TARGET" --report-path "$report" --redact || true
else
  gitleaks detect --source "$TARGET" --no-git --report-path "$report" --redact || true
fi
echo ">> gitleaks report: $report"

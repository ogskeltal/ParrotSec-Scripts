#!/usr/bin/env bash
#
# checksec-scan.sh
#
# Run checksec across a file or directory of binaries and table the binary
# protections (RELRO, canary, NX, PIE, Fortify), flagging the soft ones. Handy
# when triaging which binary to attack in a pwn/RE challenge.
#
# Usage:
#   ./checksec-scan.sh /usr/bin/some-binary
#   ./checksec-scan.sh ./bins --out checksec.txt
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
[ -n "$TARGET" ] || { echo "No file or directory given." >&2; usage 2; }
[ -e "$TARGET" ] || die "Not found: $TARGET"
have checksec || die "checksec not found (apt install checksec)."

# Build the list of ELF files to inspect.
files=()
if [ -f "$TARGET" ]; then
  files=("$TARGET")
else
  while IFS= read -r f; do
    # Only real ELF executables/objects.
    if file "$f" 2>/dev/null | grep -q 'ELF'; then files+=("$f"); fi
  done < <(find "$TARGET" -type f 2>/dev/null)
fi
[ "${#files[@]}" -gt 0 ] || die "No ELF binaries found under $TARGET."

report=""
[ -n "$OUT" ] && report="$OUT"
emit() { if [ -n "$report" ]; then tee "$report"; else cat; fi; }

{
  printf '%-30s %-6s %-7s %-4s %-4s %-8s %s\n' "BINARY" "RELRO" "CANARY" "NX" "PIE" "FORTIFY" "WEAK?"
  printf '%-30s %-6s %-7s %-4s %-4s %-8s %s\n' "------" "-----" "------" "--" "---" "-------" "-----"
  for f in "${files[@]}"; do
    # checksec JSON is the stable interface across versions.
    line=$(checksec --file="$f" --format=json 2>/dev/null)
    get() { printf '%s' "$line" | grep -oE "\"$1\":\"[^\"]*\"" | head -n1 | cut -d'"' -f4; }
    relro=$(get relro); canary=$(get canary); nx=$(get nx); pie=$(get pie); fort=$(get fortify_source)
    [ -n "$relro$canary$nx$pie" ] || { relro="?"; canary="?"; nx="?"; pie="?"; fort="?"; }
    weak=""
    [ "$canary" = "no" ] && weak="${weak}no-canary "
    [ "$nx" = "no" ]     && weak="${weak}NX-off "
    case "$pie" in no|No) weak="${weak}no-PIE " ;; esac
    case "$relro" in no|partial|Partial) weak="${weak}${relro}-relro " ;; esac
    printf '%-30s %-6s %-7s %-4s %-4s %-8s %s\n' \
      "$(basename "$f")" "${relro:-?}" "${canary:-?}" "${nx:-?}" "${pie:-?}" "${fort:-?}" "${weak:-hardened}"
  done
} | emit

[ -n "$report" ] && echo ">> Report: $report"

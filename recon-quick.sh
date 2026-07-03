#!/usr/bin/env bash
#
# recon-quick.sh
#
# First-pass recon against a single host. Runs an nmap port/service scan, then
# for any web ports found it fingerprints the server and brute-forces content.
# Output goes into a workspace-style directory. Tools that aren't installed are
# skipped, so a partial toolchain still produces useful output.
#
# Usage:
#   ./recon-quick.sh 10.10.10.10
#   ./recon-quick.sh target.tld --out ~/engagements/target
#   ./recon-quick.sh target.tld --wordlist /usr/share/wordlists/dirb/common.txt
#   ./recon-quick.sh target.tld --dry-run
#
set -uo pipefail

OUT=""
WORDLIST=""
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] $*"; return 0; fi
  "$@"
}

# Pick a directory-brute wordlist from common locations.
default_wordlist() {
  local c
  for c in \
    /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt \
    /usr/share/wordlists/dirb/common.txt \
    "$HOME/wordlists/SecLists/Discovery/Web-Content/common.txt" \
    /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# --- parse args -----------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage 0 ;;
    --dry-run|-n)  DRY_RUN=1 ;;
    --out|-o)      shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)       OUT="${1#*=}" ;;
    --wordlist|-w) shift; [ $# -gt 0 ] || die "--wordlist needs a path"; WORDLIST="$1" ;;
    --wordlist=*)  WORDLIST="${1#*=}" ;;
    -*)            die "Unknown option: $1 (try --help)" ;;
    *)             [ -z "$TARGET" ] || die "Only one target allowed."; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "No target given." >&2; usage 2; }
have nmap || die "nmap not found. Install it: sudo apt-get install -y nmap"

# --- output dir -----------------------------------------------------------
slug=$(printf '%s' "$TARGET" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-')
[ -n "$OUT" ] || OUT="./recon_${slug}_$(date +%Y-%m-%d)"
run mkdir -p "$OUT/scans" "$OUT/web"
echo ">> Target : $TARGET"
echo ">> Output : $OUT"

# --- nmap -----------------------------------------------------------------
echo ">> [1/3] nmap service scan..."
NMAP_OUT="$OUT/scans/nmap"
run nmap -Pn -sV -T4 --top-ports 1000 -oA "$NMAP_OUT" "$TARGET"

# --- find web ports -------------------------------------------------------
web_ports=()
if [ "$DRY_RUN" -ne 1 ] && [ -f "${NMAP_OUT}.gnmap" ]; then
  # Pull open ports whose service name looks like http(s).
  while IFS= read -r p; do
    web_ports+=("$p")
  done < <(grep -oE '[0-9]+/open/[^,]*http[^,]*' "${NMAP_OUT}.gnmap" 2>/dev/null \
             | cut -d/ -f1 | sort -un)
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ">> [dry-run] would parse web ports from nmap output and enumerate them."
  web_ports=(80 443)
fi

if [ "${#web_ports[@]}" -eq 0 ]; then
  echo ">> No web ports found; skipping web enumeration."
else
  echo ">> Web ports: ${web_ports[*]}"
fi

# --- per-web-port enumeration ---------------------------------------------
for port in "${web_ports[@]}"; do
  scheme="http"
  if [ "$port" = "443" ] || [ "$port" = "8443" ]; then scheme="https"; fi
  url="${scheme}://${TARGET}:${port}"
  tag="${scheme}_${port}"
  echo ">> [2/3] Fingerprinting $url"

  if have whatweb; then
    run bash -c "whatweb -a3 '$url' | tee '$OUT/web/whatweb_${tag}.txt'"
  elif have httpx; then
    run bash -c "echo '$url' | httpx -sc -title -tech-detect -o '$OUT/web/httpx_${tag}.txt'"
  else
    echo "   (no whatweb/httpx; skipping fingerprint)"
  fi

  echo ">> [3/3] Content discovery on $url"
  if [ -z "$WORDLIST" ]; then
    WORDLIST=$(default_wordlist) || true
  fi
  if [ -z "$WORDLIST" ]; then
    echo "   (no wordlist found; run wordlists-setup.sh or pass --wordlist)"
  elif have feroxbuster; then
    run feroxbuster -u "$url" -w "$WORDLIST" -q -o "$OUT/web/ferox_${tag}.txt"
  elif have ffuf; then
    run ffuf -u "${url}/FUZZ" -w "$WORDLIST" -of csv -o "$OUT/web/ffuf_${tag}.csv"
  elif have gobuster; then
    run gobuster dir -u "$url" -w "$WORDLIST" -q -o "$OUT/web/gobuster_${tag}.txt"
  else
    echo "   (no feroxbuster/ffuf/gobuster; skipping content discovery)"
  fi

  if have nuclei; then
    echo ">> nuclei on $url"
    run nuclei -u "$url" -silent -o "$OUT/web/nuclei_${tag}.txt"
  fi
done

echo
echo "================ SUMMARY ================"
echo "Output directory : $OUT"
echo "nmap             : ${NMAP_OUT}.{nmap,gnmap,xml}"
echo "web ports        : ${web_ports[*]:-none}"
echo "Next             : review the web/ files, then go deeper on findings."
echo "========================================"

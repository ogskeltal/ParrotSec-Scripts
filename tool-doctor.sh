#!/usr/bin/env bash
#
# tool-doctor.sh
#
# Check that the common pentest toolchain is present and runnable, and flag
# what's missing. Read-only; needs no root. Exits non-zero if any tool in the
# checked set is missing, so it can gate other scripts.
#
# Usage:
#   ./tool-doctor.sh              # check everything
#   ./tool-doctor.sh --missing    # only print what's missing
#   ./tool-doctor.sh --quiet      # no per-tool lines, just the summary + exit code
#
set -uo pipefail

MISSING_ONLY=0
QUIET=0

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

# group|command|package-hint
TOOLS=(
  "recon|nmap|nmap"
  "recon|masscan|masscan"
  "recon|whatweb|whatweb"
  "recon|subfinder|subfinder"
  "recon|amass|amass"
  "recon|httpx|httpx-toolkit"
  "recon|dnsx|dnsx"
  "web|gobuster|gobuster"
  "web|ffuf|ffuf"
  "web|nikto|nikto"
  "web|nuclei|nuclei"
  "web|sqlmap|sqlmap"
  "exploit|msfconsole|metasploit-framework"
  "exploit|searchsploit|exploitdb"
  "creds|hashcat|hashcat"
  "creds|john|john"
  "creds|hydra|hydra"
  "creds|hashid|hashid"
  "net|tcpdump|tcpdump"
  "net|tshark|tshark"
  "net|proxychains4|proxychains4"
  "runtime|go|golang"
  "runtime|python3|python3"
  "runtime|git|git"
)

for arg in "$@"; do
  case "$arg" in
    -h|--help)  usage 0 ;;
    --missing)  MISSING_ONLY=1 ;;
    --quiet|-q) QUIET=1 ;;
    *)          echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

present=0
missing=()
last_group=""

for entry in "${TOOLS[@]}"; do
  IFS='|' read -r group cmd hint <<< "$entry"

  if [ "$QUIET" -ne 1 ] && [ "$group" != "$last_group" ] && [ "$MISSING_ONLY" -ne 1 ]; then
    echo
    echo "[$group]"
    last_group="$group"
  fi

  if have "$cmd"; then
    present=$((present+1))
    if [ "$QUIET" -ne 1 ] && [ "$MISSING_ONLY" -ne 1 ]; then
      ver=$("$cmd" --version 2>/dev/null | head -n1 | cut -c1-48)
      printf '  %-16s ok   %s\n' "$cmd" "$ver"
    fi
  else
    missing+=("$cmd (apt: $hint)")
    if [ "$QUIET" -ne 1 ]; then
      printf '  %-16s MISSING (apt install %s)\n' "$cmd" "$hint"
    fi
  fi
done

# --- Metasploit database check (extra, non-fatal) -------------------------
if [ "$QUIET" -ne 1 ] && [ "$MISSING_ONLY" -ne 1 ]; then
  echo
  echo "[services]"
  if have systemctl; then
    pg=$(systemctl is-active postgresql 2>/dev/null || echo unknown)
    printf '  %-16s %s\n' "postgresql" "$pg (Metasploit database)"
  fi
fi

# --- summary --------------------------------------------------------------
echo
echo "================ SUMMARY ================"
echo "Present : $present / ${#TOOLS[@]}"
echo "Missing : ${#missing[@]}"
if [ "${#missing[@]}" -gt 0 ]; then
  printf '   %s\n' "${missing[@]}"
  echo "========================================"
  exit 1
fi
echo "========================================"
exit 0

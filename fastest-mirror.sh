#!/usr/bin/env bash
#
# fastest-mirror.sh
#
# Time the Parrot mirrors listed in your mirror config and report them fastest
# first. With --apply it points your apt source at the fastest one, backing up
# the file it changes. Reads the mirror list you already have; it doesn't pull a
# list from anywhere new.
#
# Usage:
#   ./fastest-mirror.sh                 # benchmark and print a ranking (no changes)
#   sudo ./fastest-mirror.sh --apply    # also switch apt to the fastest
#   ./fastest-mirror.sh --count 5
#
set -uo pipefail

APPLY=0
COUNT=0    # 0 = all
PROBE="dists/parrot/Release"

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)  usage 0 ;;
    --apply)    APPLY=1 ;;
    --count=*)  COUNT="${arg#*=}" ;;
    *)          die "Unknown option: $arg (try --help)" ;;
  esac
done
have curl || die "curl not found."

# --- gather candidate mirror base URLs ------------------------------------
# Pull hostnames from existing apt sources and the parrot mirror list, if any.
mapfile -t MIRRORS < <(
  {
    grep -rhoE 'https?://[^ ]+/parrot/?' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
    [ -f /etc/apt/mirrors/parrot.list ] && grep -oE 'https?://[^ ]+' /etc/apt/mirrors/parrot.list
    [ -f /usr/share/parrot-mirrors/mirrors.txt ] && grep -oE 'https?://[^ ]+' /usr/share/parrot-mirrors/mirrors.txt
  } | sed -E 's#(/parrot).*#\1/#' | sort -u
)

# Sensible fallbacks if nothing was found locally.
if [ "${#MIRRORS[@]}" -eq 0 ]; then
  echo ">> No mirrors found in local config; using a small known set."
  MIRRORS=(
    "https://deb.parrot.sh/parrot/"
    "https://mirror.montana.edu/parrot/"
    "https://ftp.halifax.rwth-aachen.de/parrotsec/"
    "https://mirrors.ocf.berkeley.edu/parrot/"
  )
fi

echo ">> Benchmarking ${#MIRRORS[@]} mirror(s)..."
results=$(mktemp)
for m in "${MIRRORS[@]}"; do
  url="${m%/}/$PROBE"
  # total time to fetch the Release file; mark failures as a big number.
  t=$(curl -o /dev/null -s -w '%{time_total}' --max-time 15 "$url" 2>/dev/null || echo "")
  if [ -z "$t" ] || [ "$t" = "0.000000" ]; then
    printf '999.999\t%s\n' "$m" >> "$results"
  else
    printf '%s\t%s\n' "$t" "$m" >> "$results"
  fi
  printf '   %-8s %s\n' "${t:-fail}" "$m"
done

echo
echo "================ RANKING (fastest first) ================"
ranked=$(sort -n "$results")
if [ "$COUNT" -gt 0 ]; then ranked=$(echo "$ranked" | head -n "$COUNT"); fi
echo "$ranked" | awk -F'\t' '{printf "   %-8s %s\n",$1,$2}'
best=$(sort -n "$results" | head -n1 | cut -f2)
besttime=$(sort -n "$results" | head -n1 | cut -f1)
rm -f "$results"
echo "========================================================="
[ "$besttime" = "999.999" ] && die "All mirrors failed to respond."
echo ">> Fastest: $best (${besttime}s)"

# --- apply ----------------------------------------------------------------
if [ "$APPLY" -eq 1 ]; then
  [ "$(id -u)" -eq 0 ] || die "--apply needs root."
  src="/etc/apt/sources.list.d/parrot.list"
  [ -f "$src" ] || src="/etc/apt/sources.list"
  [ -f "$src" ] || die "Could not find a parrot apt source to edit."
  cp "$src" "${src}.bak.$(date +%Y%m%d-%H%M%S)"
  host_base="${best%/}"
  # Replace the base of any parrot mirror URL with the fastest one.
  sed -i -E "s#https?://[^ ]+/parrot/?#${host_base}/#g" "$src"
  echo ">> Updated $src to use $host_base (backup saved)."
  echo ">> Run: sudo apt-get update"
fi

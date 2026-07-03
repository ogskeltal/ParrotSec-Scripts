#!/usr/bin/env bash
#
# install-parrot-missing-tools.sh
#
# Installs every tool that appears in Parrot's application menu as
# "[Not Installed]".  It does NOT rely on parrot-tools-full (which is a
# curated Recommends list and misses many menu entries).  Instead it reads
# the actual source: the "X-Parrot-Package=" field in the
# parrot-menu .desktop files on system, so it always matches your
# Parrot version.
#
# Usage:
#   sudo ./install-parrot-missing-tools.sh              # install all missing
#   ./install-parrot-missing-tools.sh --dry-run         # just show what's missing (no sudo needed)
#   sudo ./install-parrot-missing-tools.sh --with-full  # apt install parrot-tools-full first, then sweep the rest
#
set -uo pipefail   # note: no -e; we handle per-package failures ourselves

# --- config ---------------------------------------------------------------
RETRIES=4
# Where parrot-menu keeps its desktop files.
SEARCH_DIRS=(
  /usr/share/applications
  /usr/share/parrot-menu/applications
  /usr/local/share/applications
  "$HOME/.local/share/applications"
)
FIELD="X-Parrot-Package"

DRY_RUN=0
WITH_FULL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --with-full)  WITH_FULL=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- sanity checks --------------------------------------------------------
have apt-get   || die "apt-get not found. This is for Parrot/Debian systems."
have dpkg-query|| die "dpkg-query not found."

# --- 1. harvest package names from the desktop files ----------------------
echo ">> Scanning menu desktop files for '${FIELD}' entries..."
declare -A WANTED=()          # package name -> 1
found_files=0

for dir in "${SEARCH_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  # grep the field out of every .desktop file in this tree
  while IFS= read -r line; do
    found_files=1
    # line looks like: X-Parrot-Package=foo bar baz
    pkgs="${line#*=}"
    for p in $pkgs; do
      [ -n "$p" ] && WANTED["$p"]=1
    done
  done < <(grep -rhs "^[[:space:]]*${FIELD}[[:space:]]*=" "$dir" 2>/dev/null)
done

if [ "${#WANTED[@]}" -eq 0 ]; then
  if [ "$found_files" -eq 0 ]; then
    die "No parrot-menu desktop files with '${FIELD}' were found. Is parrot-menu installed?"
  fi
  die "Found desktop files but parsed zero package names. Please report this."
fi

echo ">> ${#WANTED[@]} distinct tool packages are referenced by the menu."

# --- 2. partition into installed / missing-installable / unavailable ------
echo ">> Checking install status and apt availability (this takes a moment)..."

missing_installable=()
already_installed=0
unavailable=()

is_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}
is_available() {
  # candidate exists in apt?
  apt-cache show "$1" >/dev/null 2>&1
}

for pkg in "${!WANTED[@]}"; do
  if is_installed "$pkg"; then
    already_installed=$((already_installed+1))
  elif is_available "$pkg"; then
    missing_installable+=("$pkg")
  else
    unavailable+=("$pkg")
  fi
done

# sort for stable output
mapfile -t missing_installable < <(printf '%s\n' "${missing_installable[@]}" | sort -u)
mapfile -t unavailable         < <(printf '%s\n' "${unavailable[@]}" | sort -u)

echo
echo "   already installed : ${already_installed}"
echo "   missing (installable): ${#missing_installable[@]}"
echo "   missing (no apt candidate): ${#unavailable[@]}"
echo

if [ "${#unavailable[@]}" -gt 0 ]; then
  echo ">> These are referenced by the menu but have no install candidate in your"
  echo ">> current apt sources (wrong branch, renamed, or dropped upstream):"
  printf '     %s\n' "${unavailable[@]}"
  echo
fi

if [ "${#missing_installable[@]}" -eq 0 ]; then
  echo ">> Nothing installable is missing. Everything is already installed."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ">> DRY RUN. The following ${#missing_installable[@]} packages WOULD be installed:"
  printf '     %s\n' "${missing_installable[@]}"
  echo
  echo ">> Re-run with sudo and without --dry-run to install them."
  exit 0
fi

# --- from here on we actually install, so we need root --------------------
[ "$(id -u)" -eq 0 ] || die "Installing requires root. Re-run with sudo (or use --dry-run)."

echo ">> apt-get update..."
apt-get update

# optional bulk pass
if [ "$WITH_FULL" -eq 1 ]; then
  echo ">> Installing parrot-tools-full first as a bulk pass..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing parrot-tools-full || \
    echo "!! parrot-tools-full pass had errors; the sweep below will catch the rest."
fi

# --- 3. install the missing set, batch first then per-package fallback ----
install_batch() {   # $@ = packages
  DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing "$@"
}

echo ">> Installing ${#missing_installable[@]} missing packages..."
batch_ok=0
for attempt in $(seq 1 "$RETRIES"); do
  echo ">> Batch attempt ${attempt}/${RETRIES}..."
  if install_batch "${missing_installable[@]}"; then
    batch_ok=1
    break
  fi
  echo ">> Batch attempt failed; fixing broken deps and retrying..."
  apt-get --fix-broken install -y || true
  sleep 3
done

failed=()
if [ "$batch_ok" -ne 1 ]; then
  echo
  echo ">> Batch install still failing. Falling back to one-by-one so that one"
  echo ">> bad package does not block the rest. This is slower."
  for pkg in "${missing_installable[@]}"; do
    if is_installed "$pkg"; then continue; fi
    echo "   -> $pkg"
    if ! install_batch "$pkg"; then
      failed+=("$pkg")
    fi
  done
fi

echo
echo ">> Cleaning up..."
apt-get autoremove -y || true

# --- 4. final report ------------------------------------------------------
echo
echo "================ SUMMARY ================"
still_missing=()
for pkg in "${missing_installable[@]}"; do
  is_installed "$pkg" || still_missing+=("$pkg")
done

installed_now=$(( ${#missing_installable[@]} - ${#still_missing[@]} ))
echo "Installed this run : ${installed_now}"

if [ "${#still_missing[@]}" -gt 0 ]; then
  echo "Still not installed: ${#still_missing[@]}"
  printf '   %s\n' "${still_missing[@]}"
  echo
  echo "Re-running the script sometimes clears these, since Parrot mirrors can"
  echo "drop connections mid-download."
fi

if [ "${#unavailable[@]}" -gt 0 ]; then
  echo
  echo "No apt candidate (couldn't be installed): ${#unavailable[@]}"
  echo "  (listed above; these need a different repo/branch or are gone upstream)"
fi
echo "========================================"

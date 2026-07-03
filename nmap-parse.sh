#!/usr/bin/env bash
#
# nmap-parse.sh
#
# Turn nmap XML (-oX / -oA) into a clean host/port/service table and a
# targets-by-service breakdown, plus a plain host:port list for feeding other
# tools. Uses python3 for reliable XML parsing, with a grep fallback.
#
# Usage:
#   ./nmap-parse.sh scan.xml
#   ./nmap-parse.sh scan.xml --out ./parsed
#   nmap -sV -oX - target | ./nmap-parse.sh -
#
set -uo pipefail

OUT=""
die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '/^!/d'
  exit "${1:-0}"
}

XML=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out|-o)  shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
    --out=*)   OUT="${1#*=}" ;;
    -)         XML="-" ;;
    -*)        die "Unknown option: $1 (try --help)" ;;
    *)         [ -z "$XML" ] || die "Only one input allowed."; XML="$1" ;;
  esac
  shift
done
[ -n "$XML" ] || { echo "No nmap XML given (use - for stdin)." >&2; usage 2; }

SRC=$(mktemp)
if [ "$XML" = "-" ]; then cat > "$SRC"; else [ -f "$XML" ] || die "File not found: $XML"; cat "$XML" > "$SRC"; fi
grep -q "<nmaprun" "$SRC" || die "That doesn't look like nmap XML (need -oX output)."

TABLE=$(mktemp)
HOSTPORTS=$(mktemp)
BYSVC=$(mktemp)

# Confirm python3 actually runs (not just on PATH; e.g. a broken/stub install).
python_ok() { python3 -c 'import sys' >/dev/null 2>&1; }

if python_ok; then
  python3 - "$SRC" "$TABLE" "$HOSTPORTS" "$BYSVC" <<'PY'
import sys, xml.etree.ElementTree as ET
src, table, hp, bysvc = sys.argv[1:5]
tree = ET.parse(src)
rows = []
for host in tree.getroot().findall('host'):
    st = host.find('status')
    if st is not None and st.get('state') == 'down':
        continue
    addr = ''
    for a in host.findall('address'):
        if a.get('addrtype') in ('ipv4', 'ipv6'):
            addr = a.get('addr'); break
    hn = host.find('hostnames/hostname')
    name = hn.get('name') if hn is not None else ''
    for p in host.findall('ports/port'):
        state = p.find('state')
        if state is None or state.get('state') != 'open':
            continue
        portid = p.get('portid'); proto = p.get('protocol')
        svc = p.find('service')
        sname = svc.get('name') if svc is not None else ''
        prod = ' '.join(filter(None, [
            svc.get('product') if svc is not None else '',
            svc.get('version') if svc is not None else '',
        ])) if svc is not None else ''
        rows.append((addr, name, portid, proto, sname, prod))

with open(table, 'w') as f:
    f.write('HOST\tNAME\tPORT\tPROTO\tSERVICE\tVERSION\n')
    for r in sorted(rows, key=lambda r:(r[0], int(r[2]))):
        f.write('\t'.join(x or '-' for x in r) + '\n')

with open(hp, 'w') as f:
    for r in sorted(set((r[0], r[2]) for r in rows), key=lambda r:(r[0], int(r[1]))):
        f.write(f'{r[0]}:{r[1]}\n')

svcmap = {}
for r in rows:
    svcmap.setdefault(r[4] or 'unknown', []).append(f'{r[0]}:{r[2]}')
with open(bysvc, 'w') as f:
    for s in sorted(svcmap):
        f.write(f'[{s}]\n')
        for hpv in svcmap[s]:
            f.write(f'  {hpv}\n')

print(f'{len(rows)} open ports across {len(set(r[0] for r in rows))} hosts', file=sys.stderr)
PY
else
  echo ">> python3 not found; using limited grep fallback (host/port only)." >&2
  echo -e "HOST\tPORT\tPROTO\tSERVICE" > "$TABLE"
  # crude: track current host address, emit open ports
  awk '
    /<address / && /addrtype="ipv[46]"/ {
      match($0, /addr="[^"]+"/); a=substr($0,RSTART+6,RLENGTH-7); host=a
    }
    /<port / {
      match($0,/portid="[0-9]+"/); pid=substr($0,RSTART+8,RLENGTH-9)
      match($0,/protocol="[a-z]+"/); pr=substr($0,RSTART+10,RLENGTH-11)
    }
    /state="open"/ { open=1 }
    /<service / && open==1 {
      match($0,/name="[^"]+"/); sv=substr($0,RSTART+6,RLENGTH-7)
      printf "%s\t%s\t%s\t%s\n", host, pid, pr, sv; open=0
    }
    /<\/port>/ { open=0 }
  ' "$SRC" >> "$TABLE"
  cut -f1,2 "$TABLE" | tail -n +2 | awk -F'\t' '{print $1":"$2}' | sort -u > "$HOSTPORTS"
  : > "$BYSVC"
fi

# --- print + optionally save ----------------------------------------------
echo "===== open ports ====="
if have column; then column -t -s $'\t' "$TABLE"; else cat "$TABLE"; fi
echo
echo "===== targets by service ====="
cat "$BYSVC"

if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
  cp "$TABLE" "$OUT/ports.tsv"
  cp "$HOSTPORTS" "$OUT/host-ports.txt"
  cp "$BYSVC" "$OUT/by-service.txt"
  echo
  echo ">> Wrote $OUT/{ports.tsv, host-ports.txt, by-service.txt}"
fi

rm -f "$SRC" "$TABLE" "$HOSTPORTS" "$BYSVC"

# ParrotSec-Scripts

Shell scripts for maintaining a [Parrot OS](https://parrotsec.org/) system.

## Scripts

### `install-parrot-missing-tools.sh`

Installs every tool that Parrot's application menu lists as **[Not Installed]**.

Rather than relying on `parrot-tools-full` (a curated Recommends list that misses
many menu entries), it reads the `X-Parrot-Package=` field directly from the
`parrot-menu` `.desktop` files already on your system, so it matches your Parrot
version.

**What it does**

1. Scans the menu `.desktop` files and collects the referenced package names.
2. Sorts them into three groups: already installed, missing but installable, and
   missing with no apt candidate.
3. Installs the missing-but-installable set. It runs a batch pass first (with
   retries), then falls back to one-by-one so a single bad package can't block
   the rest.
4. Prints a summary of what was installed, what failed, and what had no candidate.

**Usage**

```bash
# Preview what's missing (no changes, no root)
./install-parrot-missing-tools.sh --dry-run

# Install everything missing (needs root)
sudo ./install-parrot-missing-tools.sh

# Run parrot-tools-full first, then sweep up the rest
sudo ./install-parrot-missing-tools.sh --with-full
```

Make it executable if needed: `chmod +x install-parrot-missing-tools.sh`

**Options**

| Option            | Description                                                        |
| ----------------- | ------------------------------------------------------------------ |
| `--dry-run`, `-n` | List packages that would be installed, then exit. No root needed.  |
| `--with-full`     | Run `apt install parrot-tools-full` first, then sweep the rest.    |
| `-h`, `--help`    | Print usage and exit.                                              |

Any other flag exits with status 2.

**Requirements**

- A Parrot/Debian system with `apt-get` and `dpkg-query`.
- `parrot-menu` installed (provides the `.desktop` files).
- Root to install. The dry run does not need root.

**Exit codes**

- `0`: success, dry run, or nothing missing.
- `1`: setup error (missing `apt-get`/`dpkg-query`, no menu files, or install without root).
- `2`: unknown option.

**Notes**

- Start with `--dry-run` to preview before installing.
- The script only installs packages your own menu references. It never adds
  repositories or pulls from outside your existing apt sources.
- Packages reported as *no apt candidate* were renamed, moved to another branch,
  or dropped upstream. The script can't install these.
- Re-running often clears leftover failures, since Parrot mirrors sometimes drop
  connections mid-download.

### `toggle-services.sh`

Starts, stops, enables, or disables the services often needed for pentest work
(Metasploit's PostgreSQL, Docker, SSH, bettercap, Apache, MariaDB) so they aren't
left running at boot. Wraps `systemctl` with a default service set and a status
view.

**Usage**

```bash
# Show state of the default set (no root)
./toggle-services.sh status

# Start or stop specific services (needs root)
sudo ./toggle-services.sh start postgresql docker
sudo ./toggle-services.sh stop --all

# Enable or disable at boot
sudo ./toggle-services.sh enable ssh
sudo ./toggle-services.sh disable --all

# Preview without changing anything
./toggle-services.sh --dry-run start --all
```

**Actions:** `status`, `start`, `stop`, `restart`, `enable`, `disable`.
Pass service names explicitly, or `--all` to act on the built-in default set.
Services that aren't installed are skipped rather than treated as errors. `status`
needs no root; the mutating actions do. Exits `1` if any service fails, `2` on
bad arguments.

### `anonymize.sh`

Randomizes interface MAC addresses, spoofs the hostname, and optionally routes
traffic through Tor via Parrot's `anonsurf`. Original values are saved under
`/var/lib/parrot-scripts/` so everything can be restored.

**Usage**

```bash
# Randomize MACs, spoof hostname, start anonsurf (needs root)
sudo ./anonymize.sh on

# Restore everything
sudo ./anonymize.sh off

# Show current state (no root)
./anonymize.sh status

# Variations
sudo ./anonymize.sh on --no-tor    # skip the Tor/anonsurf step
sudo ./anonymize.sh on --mac-only  # MAC randomization only
./anonymize.sh --dry-run on         # preview, change nothing
```

**Notes**

- Uses `macchanger` if present, otherwise assigns a locally-administered random
  MAC directly via `ip`.
- Changing a MAC briefly drops the link, so expect a short network blip. Some
  wireless drivers refuse a MAC change while associated.
- The Tor step needs `anonsurf` (Parrot) installed. Without it, use `--no-tor`.
- `on` saves the true originals only once, so a second `on` won't overwrite them
  with already-spoofed values. `off` restores and clears the saved state.

### `wordlists-setup.sh`

Populates a wordlists directory. Unpacks the system `rockyou.txt` if present,
then clones well-known wordlist repos from GitHub. Existing clones are updated
with `git pull` instead of re-cloned, so re-running is cheap.

The default directory is `/usr/share/wordlists` when writable (needs root),
otherwise `~/wordlists`. Override with `--dir`.

**Usage**

```bash
# Unpack rockyou + clone the core repos
./wordlists-setup.sh

# Also clone the very large repos (Probable-Wordlists, assetnote)
./wordlists-setup.sh --large

# Install into a custom directory
./wordlists-setup.sh --dir ~/wl

# Show the repo set and exit
./wordlists-setup.sh --list
```

Core repos (cloned by default): SecLists, PayloadsAllTheThings, fuzzdb,
kkrypt0nn/wordlists, fuzz.txt, wpa2-wordlists, statistically-likely-usernames,
OneListForAll, and xajkep/wordlists. The large set (`--large`) adds
trickest/wordlists, Probable-Wordlists, and assetnote. Clones use `--depth 1`.
Run `--list` to see the full set. Exits `1` if any repo fails; re-run to retry.

### `vpn-killswitch.sh`

Fail-closed firewall around a VPN. When on, all traffic is dropped except
loopback, established connections, and traffic through the VPN interface, so a
dropped tunnel can't leak your real IP. IPv6 is blocked entirely. The current
iptables rules are backed up on `on` and restored on `off`.

**Usage**

```bash
# Turn on (tun0 assumed). Do this AFTER the VPN is connected.
sudo ./vpn-killswitch.sh on

# WireGuard, or allow a fresh tunnel to establish while active
sudo ./vpn-killswitch.sh on --iface wg0
sudo ./vpn-killswitch.sh on --server 203.0.113.5 --port 1194 --proto udp

# Restore the previous rules
sudo ./vpn-killswitch.sh off

# Check state
./vpn-killswitch.sh status
```

**Options:** `--iface` (VPN interface, default `tun0`), `--server` / `--port` /
`--proto` (permit the handshake to the VPN endpoint on the physical link,
needed to bring up a new tunnel while the killswitch is active), `--dry-run`.

**Notes**

- Turn it on after the VPN is up. Without `--server`, an already-connected
  tunnel keeps working but a new one may be blocked.
- `on` refuses to run if a killswitch is already active, so it can't overwrite
  the saved backup. Run `off` first.
- Restoring depends on the backup under `/var/lib/parrot-scripts/`. If that is
  lost, reset your firewall manually.

### `workspace.sh`

Scaffolds an engagement directory: a dated folder with the usual subdirs
(`recon/`, `scans/`, `exploits/`, `loot/`, `report/`, `notes/`) plus a
`notes.md` template and a `scope.txt`.

**Usage**

```bash
# Creates ./acme-corp_YYYY-MM-DD/
./workspace.sh acme-corp

# Under a chosen base, without the date suffix
./workspace.sh acme --base ~/engagements --no-date

# Populate an existing directory
./workspace.sh acme --force
```

The target name is slugified into a safe directory name. Existing `scope.txt`,
`notes.md`, and `README.md` are never overwritten, even with `--force`, so your
notes are safe on a re-run. No root needed.

### `tool-doctor.sh`

Checks that the common pentest toolchain is present and runnable, grouped by
purpose (recon, web, exploit, creds, net, runtime), and flags what's missing
with the apt package to install. Read-only, no root. Exits `1` if anything in
the checked set is missing, so other scripts can gate on it.

```bash
./tool-doctor.sh              # full report
./tool-doctor.sh --missing    # only what's missing
./tool-doctor.sh --quiet      # summary + exit code only
```

### `recon-quick.sh`

First-pass recon against a single host. Runs an `nmap` service scan, finds the
web ports, then fingerprints each (`whatweb`/`httpx`) and brute-forces content
(`feroxbuster`/`ffuf`/`gobuster`) plus a `nuclei` pass. Output lands in a dated
directory. Tools that aren't installed are skipped.

```bash
./recon-quick.sh 10.10.10.10
./recon-quick.sh target.tld --out ~/engagements/target
./recon-quick.sh target.tld --wordlist /usr/share/wordlists/dirb/common.txt
./recon-quick.sh target.tld --dry-run
```

Pairs with `workspace.sh` (use its `recon/` dir as `--out`) and
`wordlists-setup.sh` (for the content-discovery list). Needs `nmap`; everything
else is optional.

### `subdomain-enum.sh`

Passive subdomain enumeration. Runs whichever of `subfinder`, `assetfinder`,
and `amass` are installed, merges and dedupes, then resolves and probes with
`httpx` (or `dnsx`) to find live hosts.

```bash
./subdomain-enum.sh example.com
./subdomain-enum.sh example.com --out ~/engagements/example
./subdomain-enum.sh example.com --active     # add amass active enumeration
```

Writes `all-subs.txt` and `live-hosts.txt` to the output directory. Needs at
least one of subfinder/assetfinder/amass. `--active` does noisier, direct
enumeration; leave it off for passive-only.

### `crack.sh`

Wrapper around `hashcat`. Identifies the hash type (`hashid` /
`hashcat --identify`), picks a wordlist, and runs a dictionary attack with an
optional rules pass.

```bash
./crack.sh hashes.txt                 # identify, then crack with rockyou
./crack.sh hashes.txt --type 1000     # force mode (NTLM)
./crack.sh hashes.txt --rules best64  # add a rules pass
./crack.sh hashes.txt --identify      # show candidate modes, exit
```

Defaults to `rockyou.txt` from the standard locations (unpack it with
`wordlists-setup.sh`; gzipped lists are refused). If it can't identify the hash
unambiguously it prints candidates and asks for `--type`. On a partial crack it
suggests a larger list or a rules pass.

### `panic-wipe.sh`

**Destructive.** Securely removes engagement data and clears traces. Nothing
happens without an explicit action flag *and* a typed `WIPE` confirmation.
Always `--dry-run` first.

```bash
# Preview (touches nothing)
./panic-wipe.sh --loot ~/engagements/acme_2026-07-03 --dry-run

# Shred a loot dir, clear shell/tool history, clear clipboard
./panic-wipe.sh --loot ~/engagements/acme_2026-07-03 --history --clipboard

# Everything, including dropping kernel caches (needs root)
sudo ./panic-wipe.sh --all --loot ~/engagements/acme_2026-07-03
```

**Actions:** `--loot DIR` (shred then remove), `--history` (shell + tool
history), `--clipboard`, `--caches` (root), `--all`. Guards refuse protected and
shallow paths, but they are advisory; the typed confirmation is the real
backstop. `--yes` skips the prompt for scripted use, which removes that
backstop, so use it deliberately.

### `cve-poc.sh`

Aggregates CVE proof-of-concept sources and looks a CVE up across all of them at
once. Parrot already ships Exploit-DB (`searchsploit`), Metasploit modules, and
nuclei templates locally; this adds the two large CVE-to-GitHub PoC indexes
(`nomi-sec/PoC-in-GitHub`, `trickest/cve`) on top and cross-references
everything.

```bash
# Install/update all local sources (Exploit-DB, the PoC indexes, nuclei templates)
./cve-poc.sh sync

# Look a CVE up across Exploit-DB, GitHub PoCs, nuclei, and Metasploit
./cve-poc.sh CVE-2021-44228

# Use a custom data directory
./cve-poc.sh --dir ~/cve sync
```

Data lives in `/usr/share/cve-poc` (root) or `~/cve-poc`, override with `--dir`.
Index repos are cloned `--depth 1` and updated with `git pull` on re-sync.
Lookup exits `1` if no source has a hit. `jq` is used to parse the GitHub PoC
JSON when present, with a grep fallback.

Exploit-DB on its own is available directly through Parrot's `searchsploit`
(`searchsploit --cve 2021-44228`, `searchsploit -m <id>` to copy a PoC). This
script is only worth it for the extra GitHub-sourced PoCs and the single
cross-source view.

> PoC code is untrusted third-party code and may be malicious. Read it before
> running, ideally in a throwaway VM.

### `revshell.sh`

Prints reverse-shell one-liners for a given LHOST/LPORT, optionally URL-encoded,
and can start the matching listener. A local stand-in for revshells.com.

```bash
./revshell.sh -i tun0 -p 4444              # resolve LHOST from an interface
./revshell.sh -i 10.10.14.5 -p 4444 --type python
./revshell.sh -i tun0 -p 4444 --url-encode
./revshell.sh -i tun0 -p 4444 --listen     # start an nc/rlwrap listener
```

LHOST accepts an IP or an interface name (resolved to its IPv4). Types: bash,
sh, nc, python, php, perl, ruby, powershell, socat, msfvenom. `--url-encode`
adds an encoded copy of each payload; `--listen` execs `nc`/`ncat` (wrapped in
`rlwrap` if present).

### `serve.sh`

Stands up a quick file-transfer server (HTTP, SMB, or FTP) and prints matching
download one-liners (`wget`, `curl`, `certutil`, PowerShell, `smbclient`) for
the target.

```bash
./serve.sh                              # HTTP on 8000, serving the current dir
./serve.sh --dir /tmp/loot --port 80
./serve.sh --type smb --dir /tmp/loot   # impacket SMB share
./serve.sh --type ftp --dir /tmp/loot   # anonymous FTP (pyftpdlib)
./serve.sh --print-only                 # print commands, don't start a server
```

Host in the printed commands comes from `--lhost` (IP or interface), or is
auto-detected. HTTP uses `updog` if present, else `python3 -m http.server`. SMB
needs `impacket-smbserver`; FTP needs `pyftpdlib`.

### `screenshot-web.sh`

Screenshots a list of web hosts into a folder, using whichever tool is present
(EyeWitness, gowitness, aquatone) and falling back to headless Chromium with a
generated HTML gallery. Pairs with `subdomain-enum.sh` output.

```bash
./screenshot-web.sh live-hosts.txt
./screenshot-web.sh urls.txt --out ~/engagements/acme/shots
./screenshot-web.sh urls.txt --dry-run
```

Input is one URL or host per line; bare hosts are tried over http. The
dedicated tools write their own report; the Chromium fallback builds an
`index.html` gallery. Exits `1` if the fallback captured nothing.

### `loot-parser.sh`

Sweeps a directory for secrets: private keys, cloud credentials, tokens,
connection strings, password assignments, and interesting file names. Read-only;
writes a findings report.

```bash
./loot-parser.sh ~/engagements/acme/loot
./loot-parser.sh ./loot --out findings.txt
./loot-parser.sh ./loot --quiet          # report to file only
```

Regex-based, so expect false positives; the report is a triage starting point,
not a verdict. Pairs with `workspace.sh` (point it at the `loot/` dir).

### `linpeas-fetch.sh`

Downloads the current privilege-escalation binaries (linpeas, winpeas, pspy)
from their GitHub releases into a directory, optionally serving them over HTTP.

```bash
./linpeas-fetch.sh                    # into ./privesc-tools
./linpeas-fetch.sh --dir ~/tools
./linpeas-fetch.sh --serve            # download, then http.server on 8000
```

Always pulls the latest release, so what you hand a target isn't stale. Verifies
each file is non-empty and marks scripts/pspy executable. Exits `1` if any
download fails.

### `hashgrab.sh`

Pulls hashes out of common dump formats (impacket secretsdump, `/etc/shadow`,
Kerberos AS-REP/TGS) and sorts them into per-type files ready for `crack.sh`,
printing the hashcat mode for each.

```bash
./hashgrab.sh secretsdump.txt --out ./hashes
secretsdump.py ... | ./hashgrab.sh -
```

Recognizes NTLM (`-m 1000`), NetNTLMv2 (`5600`), Kerberos AS-REP (`18200`) /
TGS (`13100`), and Unix crypt schemes (md5crypt/sha256crypt/sha512crypt/bcrypt).
Each output file is printed with the exact `crack.sh` command to run next.

### `ntlm-relay-setup.sh`

Prepares an NTLM relay: backs up `Responder.conf`, turns off Responder's own
SMB/HTTP (required so ntlmrelayx can bind them), and prints the exact
`responder` and `ntlmrelayx` commands for two terminals. Can launch one.
`--restore` puts the config back.

```bash
sudo ./ntlm-relay-setup.sh --iface eth0 --targets targets.txt
sudo ./ntlm-relay-setup.sh --iface eth0 --targets targets.txt --launch relay
sudo ./ntlm-relay-setup.sh --restore
```

Relaying only works against hosts where SMB signing is *not* required; build the
targets file with `nmap --script smb2-security-mode -p445 <subnet>` or
crackmapexec. Needs `responder` and impacket's ntlmrelayx.

### `port-monitor.sh`

Re-scans a target on an interval and reports when open ports change since the
last scan. Useful on long engagements to catch services that come and go.

```bash
./port-monitor.sh 10.10.10.10                 # every 5 min until Ctrl-C
./port-monitor.sh target.tld --interval 900
./port-monitor.sh target.tld --once           # single scan
./port-monitor.sh target.tld --ports 1-1000
```

Stores the last open-port set and a `changes.log` in a per-target state dir,
and prints `OPENED`/`CLOSED` deltas each cycle.

### `web-tech.sh`

Deep fingerprint of one web target: HTTP headers, technology detection
(`whatweb`/`wappalyzer`), TLS certificate, and robots/sitemap. Writes and prints
a report; skips steps whose tool is missing.

```bash
./web-tech.sh https://example.com
./web-tech.sh example.com --out ./example-fingerprint.txt
```

### `notes-timestamp.sh`

Appends timestamped entries to an engagement notes file: a plain note, or a
command plus its captured output. Turns `notes.md` into a running worklog.

```bash
./notes-timestamp.sh "found anonymous FTP on 10.0.0.5"
./notes-timestamp.sh --run "nmap -sV 10.0.0.5"       # logs command + output
./notes-timestamp.sh --file ~/eng/acme/notes/notes.md --run "id"
```

The notes file defaults to `$NOTES`, then `./notes/notes.md`, then `./notes.md`,
so inside a `workspace.sh` layout it just works. `--run` exits with the wrapped
command's exit code.

## License

See [LICENSE](LICENSE).

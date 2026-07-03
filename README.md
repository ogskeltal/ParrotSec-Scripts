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
kkrypt0nn/wordlists, fuzz.txt, wpa2-wordlists. The large set (`--large`) adds
Probable-Wordlists and assetnote, which are tens of GB. Clones use
`--depth 1`. Exits `1` if any repo fails; re-run to retry.

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

## License

See [LICENSE](LICENSE).

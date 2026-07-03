# ParrotSec-Scripts

A small collection of shell scripts for maintaining a [Parrot OS](https://parrotsec.org/) system.

## Scripts

### `install-parrot-missing-tools.sh`

Installs every tool that Parrot's application menu lists as **[Not Installed]**.

Rather than relying on `parrot-tools-full` (a curated Recommends list that misses
many menu entries), it reads the `X-Parrot-Package=` field directly from the
`parrot-menu` `.desktop` files already on your system — so it always matches your
Parrot version.

**What it does**

1. Scans the menu `.desktop` files and collects the referenced package names.
2. Partitions them into: already installed, missing but installable, and missing
   with no apt candidate.
3. Installs the missing-but-installable set — a batch pass first (with retries),
   then one-by-one so a single bad package can't block the rest.
4. Prints a summary of what was installed, what failed, and what had no candidate.

**Usage**

```bash
# Preview what's missing — no changes, no root
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

- `0` — success, dry run, or nothing missing.
- `1` — setup error (missing `apt-get`/`dpkg-query`, no menu files, or install without root).
- `2` — unknown option.

**Notes**

- Start with `--dry-run` to preview before installing.
- The script only installs packages your own menu references. It never adds
  repositories or pulls from outside your existing apt sources.
- Packages reported as *no apt candidate* were renamed, moved to another branch,
  or dropped upstream — the script can't install these.
- Re-running often clears leftover failures, since Parrot mirrors sometimes drop
  connections mid-download.

### `toggle-services.sh`

Start, stop, enable, or disable the services commonly needed for pentest work
(Metasploit's PostgreSQL, Docker, SSH, bettercap, Apache, MariaDB) so they aren't
left running at boot. A thin, safe wrapper over `systemctl` with a curated default
set and a clean status view.

**Usage**

```bash
# Show state of the default set — no root
./toggle-services.sh status

# Start / stop specific services (needs root)
sudo ./toggle-services.sh start postgresql docker
sudo ./toggle-services.sh stop --all

# Enable / disable at boot
sudo ./toggle-services.sh enable ssh
sudo ./toggle-services.sh disable --all

# Preview without changing anything
./toggle-services.sh --dry-run start --all
```

**Actions:** `status`, `start`, `stop`, `restart`, `enable`, `disable`.
Pass service names explicitly, or `--all` to act on the built-in default set.
Services that aren't installed are skipped, not treated as errors. `status`
needs no root; the mutating actions do. Exits `1` if any service fails, `2` on
bad arguments.

### `anonymize.sh`

Quick identity hygiene: randomize interface MAC addresses, spoof the hostname,
and optionally route traffic through Tor via Parrot's `anonsurf`. Original values
are saved under `/var/lib/parrot-scripts/` so everything can be restored.

**Usage**

```bash
# Randomize MACs + spoof hostname + start anonsurf (needs root)
sudo ./anonymize.sh on

# Restore everything
sudo ./anonymize.sh off

# Show current state — no root
./anonymize.sh status

# Variations
sudo ./anonymize.sh on --no-tor    # skip the Tor/anonsurf step
sudo ./anonymize.sh on --mac-only  # MAC randomization only
./anonymize.sh --dry-run on         # preview, change nothing
```

**Notes**

- Uses `macchanger` if present, otherwise assigns a locally-administered random
  MAC directly via `ip`.
- Changing a MAC briefly drops the link — expect a short network blip. Some
  wireless drivers refuse a MAC change while associated.
- The Tor step needs `anonsurf` (Parrot) installed; without it, use `--no-tor`.
- `on` saves the true originals only once, so a second `on` won't overwrite them
  with already-spoofed values. `off` restores and clears the saved state.

## License

See [LICENSE](LICENSE).

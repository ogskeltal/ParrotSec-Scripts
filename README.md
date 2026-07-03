install-parrot-missing-tools.sh

Installs every tool that Parrot OS lists in its application menu as [Not Installed].

Instead of using parrot-tools-full (a curated Recommends list that misses many menu entries), the script reads the X-Parrot-Package= field from the parrot-menu .desktop files already on your system. It installs what your menu actually references, so it matches your Parrot version.

What it does


Scans the menu .desktop files for X-Parrot-Package= entries and collects the package names.
Sorts them into threeinstall-parrot-missing-tools.sh

Installs every tool that Parrot OS lists in its application menu as [Not Installed].

Instead of using parrot-tools-full (a curated Recommends list that misses many menu entries), the script reads the X-Parrot-Package= field from the parrot-menu .desktop files already on your system. It installs what your menu actually references, so it matches your Parrot version.
What it does

    Scans the menu .desktop files for X-Parrot-Package= entries and collects the package names.
    Sorts them into three groups: already installed, missing but installable, and missing with no apt candidate.
    Installs the missing-but-installable packages. It tries a batch install first, then falls back to one-by-one so one bad package can't block the rest.
    Prints a summary of what was installed, what failed, and what had no candidate.

Requirements

    A Parrot/Debian system with apt-get and dpkg-query.
    parrot-menu installed (provides the .desktop files).
    Root for installing. The dry run does not need root.

Usage
bash

# Install everything missing (needs root)
sudo ./install-parrot-missing-tools.sh

# Show what's missing, no changes, no sudo
./install-parrot-missing-tools.sh --dry-run

# Run parrot-tools-full first, then sweep the rest
sudo ./install-parrot-missing-tools.sh --with-full

Make it executable if needed:
bash

chmod +x install-parrot-missing-tools.sh

Options
Option	Description
--dry-run, -n	List packages that would be installed, then exit. No changes, no root.
--with-full	Run apt install parrot-tools-full first, then sweep up what it missed.
-h, --help	Print usage and exit.

Any other flag exits with status 2.
Where it looks

The script searches these directories and skips ones that don't exist:

    /usr/share/applications
    /usr/share/parrot-menu/applications
    /usr/local/share/applications
    ~/.local/share/applications

How the install works

The batch install (apt-get install -y --fix-missing) runs first and retries up to 4 times, running apt-get --fix-broken install between attempts. The retries are there because Parrot mirrors sometimes drop connections mid-download.

If the batch still fails, the script installs each remaining package on its own so one failure doesn't stop the others. This is slower. It finishes with apt-get autoremove -y.

The script runs without set -e on purpose. It handles package failures itself instead of aborting on the first error.
Output and exit codes

A run prints a status count like:

   already installed : 142
   missing (installable): 18
   missing (no apt candidate): 3

Packages with no apt candidate are listed separately. They're referenced by the menu but aren't in your current apt sources, usually because they moved to a different branch, were renamed, or were dropped upstream. The script can't install these.

Exit codes:

    0: success, dry run, or nothing missing.
    1: setup error (missing apt-get/dpkg-query, no menu files, or install without root).
    2: unknown option.

Troubleshooting

    No menu files found: parrot-menu probably isn't installed.
    Packages still not installed: re-run the script. Mirrors dropping connections is the usual cause, and a second pass often clears it.
    No apt candidate: the package isn't available from your sources. You'd need a different Parrot branch, or it's gone upstream.

Notes

    Start with --dry-run to preview before installing.
    The script only installs packages your own menu references. It doesn't add repositories or pull from outside your apt sources.
 groups: already installed, missing but installable, and missing with no apt candidate.
Installs the missing-but-installable packages. It tries a batch install first, then falls back to one-by-one so one bad package can't block the rest.
Prints a summary of what was installed, what failed, and what had no candidate.


Requirements


A Parrot/Debian system with apt-get and dpkg-query.
parrot-menu installed (provides the .desktop files).
Root for installing. The dry run does not need root.


Usage


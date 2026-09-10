#!/usr/bin/env bash
#
# install-dependencies.sh — installs the Python and system tooling required
# by the AD Pentest Lab (nmap, Impacket, BloodHound, Certipy, kerbrute, ...).
#
# Exits on the first failure instead of silently continuing, and resolves
# requirements.txt relative to this script so it works regardless of the
# caller's current working directory.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
KERBRUTE_URL="https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64"

# Install Python dependencies (shared across the security labs)
pip install -r "${SCRIPT_DIR}/../../requirements.txt"

# Install required system tools.
#
# DEBIAN_FRONTEND=noninteractive and NEEDRESTART_MODE=a keep apt/needrestart
# from opening an interactive "which services should be restarted?" prompt.
# Without these, apt can appear to hang indefinitely at "Checking init
# scripts..." on hosts where stdin isn't a real TTY (e.g. automated runs).
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

sudo -E apt update
sudo -E apt install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    nmap \
    crackmapexec \
    smbclient \
    ldap-utils \
    bloodhound-python \
    impacket-scripts \
    seclists \
    responder \
    enum4linux-ng

# Remove packages that apt marked as automatically installed and no longer
# required (e.g. leftover python3.x packages from a prior distro upgrade).
# Safe no-op if there's nothing to remove.
sudo -E apt autoremove -y

# Install Certipy
pip install certipy-ad

# Install kerbrute
tmp_kerbrute="$(mktemp)"
trap 'rm -f "${tmp_kerbrute}"' EXIT

wget --quiet --output-document="${tmp_kerbrute}" "${KERBRUTE_URL}"
chmod +x "${tmp_kerbrute}"
sudo mv "${tmp_kerbrute}" /usr/local/bin/kerbrute
trap - EXIT

echo "Installation complete!"
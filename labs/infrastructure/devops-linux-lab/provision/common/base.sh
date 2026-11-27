# shellcheck shell=bash
set -euo pipefail
[ -f /var/lib/.base_provisioned ] && { echo "Base already done, skipping"; exit 0; }
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y curl wget git jq vim tree tmux htop net-tools \
    bash-completion python3 python3-pip netcat-openbsd openssl
  systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y curl wget git jq vim tree tmux net-tools \
    bash-completion python3 python3-pip nmap-ncat openssl
  # htop comes from EPEL on Enterprise Linux; do not fail the build without it.
  dnf install -y htop 2>/dev/null || echo "htop not available in the enabled repositories, skipping"
  systemctl enable --now sshd 2>/dev/null || true
elif command -v zypper >/dev/null 2>&1; then
  zypper install -y curl wget git jq vim tree tmux htop net-tools \
    bash-completion python3 python3-pip netcat openssl
  systemctl enable --now sshd 2>/dev/null || true
fi
touch /var/lib/.base_provisioned

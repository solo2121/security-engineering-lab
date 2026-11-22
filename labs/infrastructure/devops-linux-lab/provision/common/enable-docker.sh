# shellcheck shell=bash
systemctl enable --now docker 2>/dev/null || true
usermod -aG docker vagrant 2>/dev/null || true

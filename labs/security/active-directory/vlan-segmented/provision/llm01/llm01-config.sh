# shellcheck shell=bash
set -euo pipefail
echo "================================================================"
echo "llm01: OWASP Top 10 for LLM Applications (2025) Training Lab"
echo "https://genai.owasp.org/initiatives/top-10-for-llm-and-genai/"
echo "================================================================"
echo "WARNING: intentionally vulnerable app. Isolated lab VM only —"
echo "never expose this host to the public internet. All data is"
echo "synthetic; all dangerous actions are simulated. See llm-lab/README.md."

# Idempotency: allow all outbound before (re)provisioning, in case
# a previous run already applied the egress restriction at the
# bottom of this script - otherwise a re-run's apt-get/pip would fail.
iptables -P OUTPUT ACCEPT 2>/dev/null || true
iptables -F OUTPUT 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip iptables ca-certificates curl

id -u llmlab >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin llmlab

rm -rf /opt/llm-lab
mkdir -p /opt/llm-lab
cp -a /tmp/llm-lab-src/. /opt/llm-lab/
rm -rf /tmp/llm-lab-src

mkdir -p /opt/llm-lab/data/sandbox
chown -R llmlab:llmlab /opt/llm-lab
chmod 750 /opt/llm-lab/data/sandbox

python3 -m venv /opt/llm-lab/venv
/opt/llm-lab/venv/bin/pip install --upgrade pip --quiet
/opt/llm-lab/venv/bin/pip install -r /opt/llm-lab/requirements.txt --quiet
chown -R llmlab:llmlab /opt/llm-lab/venv

cp /opt/llm-lab/systemd/llm-owasp-lab.service /etc/systemd/system/llm-owasp-lab.service
systemctl daemon-reload
systemctl enable llm-owasp-lab.service
systemctl restart llm-owasp-lab.service

echo "Waiting for llm-owasp-lab to report healthy..."
healthy=0
for i in $(seq 1 15); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "[OK] llm-owasp-lab service is healthy."
    healthy=1
    break
  fi
  sleep 2
done
if [ "$healthy" -ne 1 ]; then
  echo "[WARN] llm-owasp-lab did not report healthy in time."
  echo "       Diagnose with: systemctl status llm-owasp-lab --no-pager"
  echo "                      journalctl -u llm-owasp-lab -n 50 --no-pager"
fi

# Egress isolation (defense in depth): after setup, restrict this
# VM's outbound traffic to the lab's VLAN supernet only (covers
# all VLANs so DNS via DC01 on vlan10 still works). Vagrant's own
# SSH management channel is inbound/port-forwarded and doesn't
# depend on outbound internet routing, so `vagrant ssh` /
# `vagrant provision` keep working; this only stops the app (or a
# bug in it) from reaching the public internet.
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -d 172.28.0.0/16 -j ACCEPT
iptables -A OUTPUT -j DROP

echo "================================================================"
echo "llm01 ready."
echo "API:        http://@@VM_IP@@:8000"
echo "Swagger UI: http://@@VM_IP@@:8000/docs"
echo "Categories: http://@@VM_IP@@:8000/owasp/categories"
echo "Smoke test: llm-lab/scripts/smoke_test.sh (run from the host)"
echo "================================================================"

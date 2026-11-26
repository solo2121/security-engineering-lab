# shellcheck shell=bash
set -euo pipefail
echo "================================================================"
echo "llm01: OWASP Top 10 for LLM Applications (2025) Training Lab"
echo "https://genai.owasp.org/initiatives/top-10-for-llm-and-genai/"
echo "================================================================"
echo "WARNING: intentionally vulnerable app. Isolated lab VM only —"
echo "never expose this host to the public internet. All data is"
echo "synthetic; all dangerous actions are simulated. See llm-lab/README.md."

# Idempotency: allow all outbound before (re)provisioning, in case a
# previous run already applied the egress restriction at the bottom
# of this script — otherwise a re-run's apt-get, pip or image pull would fail.
iptables -P OUTPUT ACCEPT 2>/dev/null || true
iptables -F OUTPUT 2>/dev/null || true
iptables -F DOCKER-USER 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive

# Wait for working DNS before touching apt. A resolver that is still coming
# up, or a briefly unreachable mirror, otherwise fails the whole provision
# with "Temporary failure resolving ...".
dns_ok=0
for _ in $(seq 1 30); do
  if getent hosts archive.ubuntu.com >/dev/null 2>&1; then
    dns_ok=1
    break
  fi
  sleep 2
done
if [ "$dns_ok" -ne 1 ]; then
  echo "[FAIL] llm01 cannot resolve archive.ubuntu.com after 60 seconds."
  echo "       Check the host: the libvirt default network must be active"
  echo "       (virsh net-list --all), and a host firewall or Docker must not"
  echo "       block the VM's DNS or forwarded traffic. Then run:"
  echo "       vagrant provision llm01"
  exit 1
fi

APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
# shellcheck disable=SC2086
apt-get $APT_OPTS update -y
# shellcheck disable=SC2086
apt-get $APT_OPTS install -y --no-install-recommends \
  python3 python3-venv python3-pip iptables ca-certificates curl

# A re-run starts from a clean slate: stop a previous Docker deployment first.
if command -v docker >/dev/null 2>&1 && [ -f /opt/llm-lab/docker-compose.yml ]; then
  (cd /opt/llm-lab && docker compose --profile lab --profile ollama down) >/dev/null 2>&1 || true
fi
systemctl disable --now llm-lab-docker.service llm-owasp-lab.service >/dev/null 2>&1 || true

id -u llmlab >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin llmlab

rm -rf /opt/llm-lab
mkdir -p /opt/llm-lab
cp -a /tmp/llm-lab-src/. /opt/llm-lab/
rm -rf /tmp/llm-lab-src

# Settings shared by the egress script and the helper commands.
mkdir -p /etc/default
cat >/etc/default/llm-lab <<EOF
LAB_SUBNET=@@LAB_SUBNET@@
LLM01_IP=@@LLM01_IP@@
EOF
chmod 644 /etc/default/llm-lab
install -m 755 /opt/llm-lab/scripts/llm01-egress.sh /usr/local/sbin/llm01-egress
install -m 755 /opt/llm-lab/scripts/llm01-ollama.sh /usr/local/sbin/llm01-ollama
install -m 644 /opt/llm-lab/systemd/llm01-egress.service /etc/systemd/system/llm01-egress.service

wait_healthy() {
  for _ in $(seq 1 45); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# Preferred runtime: the hardened container from docker-compose.yml, started
# at boot by llm-lab-docker.service. Returns non-zero on any failure so the
# caller can fall back to the plain Python service.
setup_docker() {
  # shellcheck disable=SC2086
  apt-get $APT_OPTS install -y --no-install-recommends docker.io docker-compose-v2 || return 1
  systemctl enable --now docker || return 1
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 2
  done
  docker info >/dev/null 2>&1 || return 1

  # Fresh random keys for the secure API; they stay on this VM in a root-only file.
  (
    cd /opt/llm-lab || exit 1
    umask 077
    cp .env.example .env
    python3 - <<'PY'
import re, secrets
text = open(".env").read()
text = re.sub("CHANGE_ME", lambda _: secrets.token_urlsafe(32), text)
text += "\n# Set by the llm01 provisioner\nLLM_LAB_BIND=0.0.0.0\nLLM_LAB_VULN_PORT=8000\n"
open(".env", "w").write(text)
PY
  ) || return 1
  chmod 600 /opt/llm-lab/.env

  # Docker Hub and PyPI are reachable only during provisioning, so retry the build.
  built=0
  for attempt in 1 2 3; do
    if (cd /opt/llm-lab && docker compose --profile lab build llm-lab-vulnerable); then
      built=1
      break
    fi
    echo "[WARN] image build failed (attempt $attempt of 3); retrying."
    sleep 10
  done
  [ "$built" -eq 1 ] || return 1

  install -m 644 /opt/llm-lab/systemd/llm-lab-docker.service /etc/systemd/system/llm-lab-docker.service
  systemctl daemon-reload
  systemctl enable llm-lab-docker.service
  systemctl restart llm-lab-docker.service || return 1
  wait_healthy
}

# Fallback runtime: the same app in a Python venv under systemd.
setup_venv() {
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
  wait_healthy
}

runtime=""
echo "Setting up the lab in Docker (first build takes a few minutes)..."
if setup_docker; then
  runtime="docker"
else
  echo "[WARN] the Docker setup failed; falling back to the Python service."
  echo "       Diagnose with: systemctl status docker llm-lab-docker --no-pager"
  echo "                      docker compose -f /opt/llm-lab/docker-compose.yml logs --tail 50"
  (cd /opt/llm-lab && docker compose --profile lab down) >/dev/null 2>&1 || true
  systemctl disable --now llm-lab-docker.service >/dev/null 2>&1 || true
  rm -f /opt/llm-lab/.env
  if setup_venv; then
    runtime="python (systemd)"
  fi
fi

if [ -z "$runtime" ]; then
  echo "[FAIL] the lab did not become healthy with Docker or with the Python service."
  echo "       Diagnose with: journalctl -u llm-lab-docker -u llm-owasp-lab -n 50 --no-pager"
  exit 1
fi
echo "[OK] the lab is healthy (runtime: $runtime)."

# Egress isolation (defense in depth): after setup, restrict outbound traffic
# to the lab subnet, for the host and for containers alike. The egress unit
# reapplies the rules on every boot. Vagrant's own SSH management channel is
# inbound/port-forwarded and doesn't depend on outbound internet routing, so
# `vagrant ssh` / `vagrant provision` keep working; this only stops the app
# (or a bug in it) from reaching the public internet.
systemctl daemon-reload
systemctl enable llm01-egress.service
systemctl restart llm01-egress.service

echo "================================================================"
echo "llm01 ready. It starts by itself on every boot (runtime: $runtime)."
echo "API:        http://@@LLM01_IP@@:8000"
echo "Swagger UI: http://@@LLM01_IP@@:8000/docs"
echo "Categories: http://@@LLM01_IP@@:8000/owasp/categories"
echo "Challenges: http://@@LLM01_IP@@:8000/challenges"
if [ "$runtime" = "docker" ]; then
  echo "API keys:   sudo cat /opt/llm-lab/.env   (inside the VM; generated for this VM only)"
  echo "Real model: sudo llm01-ollama enable     (optional, downloads about 1.5 GB)"
fi
echo "Smoke test: llm-lab/scripts/smoke_test.sh (run from the host)"
echo "================================================================"

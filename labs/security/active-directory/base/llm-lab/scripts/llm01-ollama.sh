#!/usr/bin/env bash
# Opt-in real local model for the llm01 VM.
#
#   sudo llm01-ollama enable    download the models once, then switch the lab to Ollama
#   sudo llm01-ollama disable   go back to the offline mock model
#   sudo llm01-ollama status
#
# The VM has no internet access once provisioned. "enable" opens egress only
# for the download (about 1.5 GB), closes it again when it finishes or fails,
# and then starts Ollama on an internal-only network.
set -euo pipefail

APP_DIR="${LLM01_APP_DIR:-/opt/llm-lab}"
ENV_FILE="$APP_DIR/.env"
EGRESS="${LLM01_EGRESS:-/usr/local/sbin/llm01-egress}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo llm01-ollama ${1:-enable}" >&2
  exit 1
fi
cd "$APP_DIR"

compose() { docker compose --profile lab "$@"; }

set_provider() {
  if grep -q '^LLM_LAB_PROVIDER=' "$ENV_FILE"; then
    sed -i "s/^LLM_LAB_PROVIDER=.*/LLM_LAB_PROVIDER=$1/" "$ENV_FILE"
  else
    echo "LLM_LAB_PROVIDER=$1" >>"$ENV_FILE"
  fi
}

wait_healthy() {
  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

case "${1:-status}" in
  enable)
    trap '"$EGRESS" apply' EXIT
    "$EGRESS" lift
    docker compose --profile ollama --profile ollama-pull pull ollama ollama-pull
    docker compose --profile ollama-pull run --rm ollama-pull
    "$EGRESS" apply
    trap - EXIT
    set_provider ollama
    compose --profile ollama up -d ollama llm-lab-vulnerable
    if wait_healthy; then
      echo "[OK] the lab now uses the Ollama model."
    else
      echo "[WARN] the lab did not become healthy; run: llm01-ollama disable" >&2
      exit 1
    fi
    ;;
  disable)
    set_provider mock
    compose --profile ollama stop ollama 2>/dev/null || true
    compose up -d llm-lab-vulnerable
    echo "[OK] the lab uses the offline mock model."
    ;;
  status)
    grep '^LLM_LAB_PROVIDER=' "$ENV_FILE" || echo "LLM_LAB_PROVIDER is not set (mock)"
    compose --profile ollama ps
    ;;
  *)
    echo "usage: llm01-ollama enable|disable|status" >&2
    exit 2
    ;;
esac

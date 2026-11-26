#!/usr/bin/env bash
# Egress isolation for the llm01 VM.
#
#   llm01-egress apply   restrict outbound traffic to the lab subnet
#   llm01-egress lift    allow all outbound (setup, image pulls, model downloads)
#
# Two paths leave this VM, and both are closed:
#   - traffic the host itself starts   -> the OUTPUT chain
#   - traffic a container starts       -> forwarded, so the DOCKER-USER chain
# Docker traffic never touches OUTPUT, so without the second rule the lab
# container could reach the internet even though the host cannot.
# The settings come from /etc/default/llm-lab (written by the provisioner).
set -euo pipefail

ENV_FILE="${LLM01_ENV_FILE:-/etc/default/llm-lab}"
if [ ! -r "$ENV_FILE" ]; then
  echo "llm01-egress: cannot read $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$ENV_FILE"
: "${LAB_SUBNET:?LAB_SUBNET is not set in $ENV_FILE}"

have_docker_chain() { iptables -n -L DOCKER-USER >/dev/null 2>&1; }

lift() {
  iptables -P OUTPUT ACCEPT
  iptables -F OUTPUT
  if have_docker_chain; then iptables -F DOCKER-USER; fi
}

apply() {
  lift
  iptables -A OUTPUT -o lo -j ACCEPT
  iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -d "$LAB_SUBNET" -j ACCEPT
  iptables -A OUTPUT -j DROP
  if have_docker_chain; then
    iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -A DOCKER-USER -d "$LAB_SUBNET" -j RETURN
    iptables -A DOCKER-USER -i docker0 ! -o docker0 -j DROP
    iptables -A DOCKER-USER -i br-+ ! -o br-+ -j DROP
  fi
}

case "${1:-}" in
  apply) apply ;;
  lift) lift ;;
  *) echo "usage: llm01-egress apply|lift" >&2; exit 2 ;;
esac

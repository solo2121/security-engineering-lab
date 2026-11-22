#!/bin/bash
set -e

LOG_FILE="/var/log/lab-network.log"
mkdir -p /var/log/lab
exec 1> >(tee -a "$LOG_FILE") 2>&1

echo "$(date) - Configuring network for @@IP_ADDRESS@@"

# Wait for all interfaces to be enumerated
sleep 5

DEFAULT_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)

# Find the interface that does NOT have the management IP (@@NAT_IP_PREFIX@@.x for the provider's NAT)
TARGET_IF=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'); do
  IF_IP=$(ip addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
  if [ -n "$IF_IP" ] && echo "$IF_IP" | grep -qv '@@NAT_IP_PREFIX@@'; then
    TARGET_IF="$iface"
    break
  fi
done

if [ -z "$TARGET_IF" ]; then
  TARGET_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E "^lo|$DEFAULT_IF" | head -n 1)
fi
if [ -z "$TARGET_IF" ]; then
  TARGET_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n 1)
fi

echo "Using interface: $TARGET_IF"

dhclient -r "$TARGET_IF" 2>/dev/null || true
pkill -9 dhclient 2>/dev/null || true

ip addr flush dev "$TARGET_IF" 2>/dev/null || true
ip route flush dev "$TARGET_IF" 2>/dev/null || true
ip addr add @@IP_ADDRESS@@/24 dev "$TARGET_IF"
ip link set "$TARGET_IF" up

# shellcheck disable=SC2157 # @@GATEWAY@@ is filled in (possibly empty) when the Vagrantfile renders this script
if [ -n "@@GATEWAY@@" ]; then
  ip route add default via @@GATEWAY@@ dev "$TARGET_IF" 2>/dev/null || true
fi

# shellcheck disable=SC2157 # @@DNS_SERVER@@ is filled in (possibly empty) when the Vagrantfile renders this script
if [ -n "@@DNS_SERVER@@" ]; then
  echo "nameserver @@DNS_SERVER@@" > /etc/resolv.conf
  echo "search lab.local" >> /etc/resolv.conf
fi

echo "$(date) - Network configured: $TARGET_IF = @@IP_ADDRESS@@/24 gw=@@GATEWAY@@"

# shellcheck shell=bash
          if [ "${DEBUG:-false}" = "true" ]; then set -x; fi
          set -euo pipefail

          MASTER="@@MASTER_IP@@"
          WORKER_IP="@@CFG_IP@@"
          WORKER_NAME="@@NAME@@"
          TOKEN_FILE=/vagrant/.k3s_token
          CLUSTER_STATE=/vagrant/.cluster_state.json

          export PATH=$PATH:/usr/local/bin:/var/lib/rancher/k3s/bin

          get_iface() {
            local ip="$1"
            iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            if [ -z "$iface" ]; then
              iface=$(ip route get "$ip" 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
            fi
            if [ -z "$iface" ]; then
              iface=$(ip -o link show | awk -F': ' '$2 ~ /^(ens|enp|eth)/ {print $2; exit}')
            fi
            [ -z "$iface" ] && iface="eth0"
            echo "$iface"
          }

          echo "Configuring kernel modules for Kubernetes..."
          modprobe br_netfilter || true
          modprobe overlay || true
          modprobe vxlan || true
          cat <<EOF >/etc/modules-load.d/k8s.conf
        overlay
        br_netfilter
        vxlan
EOF
          echo br_netfilter | tee /etc/modules-load.d/br_netfilter.conf >/dev/null
          cat <<EOF >/etc/sysctl.d/99-kubernetes.conf
        net.bridge.bridge-nf-call-iptables=1
        net.bridge.bridge-nf-call-ip6tables=1
        net.ipv4.ip_forward=1
        net.ipv4.conf.all.rp_filter=0
        net.ipv4.conf.default.rp_filter=0
EOF
          sysctl --system
          apt-get install -y iptables arptables ebtables 2>/dev/null || true
          update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
          update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
          swapoff -a || true
          sed -i '/ swap / s/^/#/' /etc/fstab 2>/dev/null || true

          echo "Waiting for master cluster ready signal..."
          WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"
          WAITED=0
          until [ -f "$CLUSTER_STATE" ] && grep -q '"cluster_ready": true' "$CLUSTER_STATE" 2>/dev/null; do
            if [ "$WAITED" -ge "$WAIT_TIMEOUT" ]; then
              echo "ERROR: Timed out after ${WAIT_TIMEOUT}s waiting for $CLUSTER_STATE"
              if nc -z -w3 "$MASTER" 6443 2>/dev/null; then
                echo "  Master API ${MASTER}:6443 is reachable, so /vagrant is probably not shared"
                echo "  read-write with the master. Start devops-1 first, then the workers, so they receive the files at boot."
              else
                echo "  Master API ${MASTER}:6443 is NOT reachable from this worker."
                echo "  Check that devops-1 uses ${MASTER} (vagrant ssh devops-1 -c 'ip -4 -br addr')."
              fi
              exit 1
            fi
            echo " Waiting for cluster ready... (${WAITED}s/${WAIT_TIMEOUT}s)"; sleep 8
            WAITED=$((WAITED + 8))
          done
          sleep 15

          if [ ! -s "$TOKEN_FILE" ]; then
            echo "ERROR: K3s token file is missing or empty: $TOKEN_FILE"
            exit 1
          fi
          TOKEN=$(cat "$TOKEN_FILE")

          if systemctl is-active --quiet k3s-agent 2>/dev/null; then
            echo "Worker already joined"
            exit 0
          fi

          IFACE=$(get_iface "${WORKER_IP}")
          echo "Detected interface for worker: ${IFACE}"

          curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent             --node-name ${WORKER_NAME}             --server https://$MASTER:6443             --token $TOKEN             --node-ip $WORKER_IP" sh -

          systemctl enable --now k3s-agent || true
          echo "Worker ${WORKER_NAME} joined successfully"

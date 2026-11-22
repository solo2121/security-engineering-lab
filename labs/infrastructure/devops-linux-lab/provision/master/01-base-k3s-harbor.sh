# shellcheck shell=bash
          if [ "${DEBUG:-false}" = "true" ]; then set -x; fi
          set -euo pipefail

          MASTER_IP="@@CFG_IP@@"
          HARBOR_PROJECT="@@HARBOR_PROJECT@@"
          HARBOR_CHART_VERSION="@@HARBOR_CHART_VERSION@@"
          INGRESS_NGINX_VERSION="@@INGRESS_NGINX_VERSION@@"
          K3S_VERSION="@@K3S_VERSION@@"
          DOCKER_VERSION="@@DOCKER_VERSION@@"
          HARBOR_PASS=@@HARBOR_PASS_ESCAPED@@
          TOKEN_PATH=/vagrant/.k3s_token
          CLUSTER_READY=/vagrant/.cluster_ready
          FAST_BOOT="@@FAST_BOOT@@"
          LAB_PROFILE="@@LAB_PROFILE@@"
          K8S_API_HOST_PORT="@@K8S_API_HOST_PORT@@"
          CACHE_MODE="@@CACHE_MODE@@"
          PROVIDER="@@PROVIDER@@"
          AIRGAP_IMAGES=(
@@AIRGAP_IMAGES_LIST@@
          )

          export PATH=$PATH:/usr/local/bin:/var/lib/rancher/k3s/bin
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

          STATE_DIR="/var/lib/lab_state"
          mkdir -p "$STATE_DIR"
          transition_state() {
            local new_state="$1"
            echo "$new_state" > "$STATE_DIR/current_state"
            echo "$(date -Iseconds): $new_state" >> "$STATE_DIR/state_history"
          }
          transition_state "starting"

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

          wait_for() {
            local check_func="$1"
            local message="$2"
            local max_attempts="${3:-60}"
            local attempt=0
            while ! $check_func 2>/dev/null; do
              attempt=$((attempt + 1))
              if [ "$attempt" -ge "$max_attempts" ]; then
                echo "ERROR: Timeout waiting for: $message"
                return 1
              fi
              echo " Waiting for $message... ($attempt/$max_attempts)"
              sleep 5
            done
            echo "Ready: $message"
          }

          check_k3s_service() { systemctl is-active --quiet k3s; }
          check_api_ready() { curl -sk https://127.0.0.1:6443/readyz >/dev/null 2>&1; }
          check_kubectl_ready() { kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes >/dev/null 2>&1; }

          check_node_registered() {
            kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get node devops-1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx "True"
          }

          echo "Waiting for network to fully stabilize..."
          for i in $(seq 1 60); do
            if ip route get 8.8.8.8 >/dev/null 2>&1; then
              echo "Network routing is ready"
              break
            fi
            echo "Waiting for routing table... ($i/60)"
            sleep 3
          done

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

          echo "Configuring iptables for K3s compatibility..."
          apt-get install -y iptables arptables ebtables 2>/dev/null || true
          update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
          update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

          echo "Disabling swap..."
          swapoff -a || true
          sed -i '/ swap / s/^/#/' /etc/fstab 2>/dev/null || true

          RESTART_DOCKER=0
          if ! systemctl is-active --quiet docker 2>/dev/null; then
            if ! command -v docker >/dev/null 2>&1; then
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              apt-get install -y ca-certificates curl gnupg lsb-release
              install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              chmod a+r /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
              apt-get update -qq

              DOCKER_INSTALL_METHOD=""
              DOCKER_ACTUAL_VERSION=""
              UBUNTU_VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"
              UBUNTU_CODENAME="$(lsb_release -cs)"
              VERSION_STRING_CODENAME="5:${DOCKER_VERSION}-1~ubuntu.${UBUNTU_VERSION_ID}~${UBUNTU_CODENAME}"

              if apt-cache madison docker-ce 2>/dev/null | grep -q "$VERSION_STRING_CODENAME"; then
                apt-get install -y docker-ce="$VERSION_STRING_CODENAME" docker-ce-cli="$VERSION_STRING_CODENAME" containerd.io docker-buildx-plugin docker-compose-plugin
                DOCKER_INSTALL_METHOD="exact"
              elif apt-cache madison docker-ce 2>/dev/null | grep -q "${DOCKER_VERSION}"; then
                MATCHED_VERSION=$(apt-cache madison docker-ce 2>/dev/null | grep "${DOCKER_VERSION}" | head -1 | awk '{print $3}')
                apt-get install -y docker-ce="$MATCHED_VERSION" docker-ce-cli="$MATCHED_VERSION" containerd.io docker-buildx-plugin docker-compose-plugin
                DOCKER_INSTALL_METHOD="madison_match"
              else
                echo "WARNING: Exact Docker version not found - installing latest"
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                DOCKER_INSTALL_METHOD="latest_fallback"
              fi
              DOCKER_ACTUAL_VERSION="$(docker --version | cut -d' ' -f3 | tr -d ',')"

              cat > /var/lib/docker_installation_record <<EOF
        DESIRED_VERSION=${DOCKER_VERSION}
        ACTUAL_VERSION=${DOCKER_ACTUAL_VERSION}
        INSTALL_METHOD=${DOCKER_INSTALL_METHOD}
        INSTALLED_AT=$(date -Iseconds)
EOF
              if [ "${DOCKER_VERSION}" != "${DOCKER_ACTUAL_VERSION}" ] && [ "${FAST_BOOT}" != "true" ]; then
                echo "WARNING: Docker version drift detected. Continuing anyway."
              fi
            fi
            systemctl enable --now docker
            usermod -aG docker vagrant || true
            RESTART_DOCKER=1
          fi

          # Docker daemon configuration
          if [ ! -f /etc/docker/daemon.json ] || [ "$RESTART_DOCKER" -eq 1 ]; then
            cat > /etc/docker/daemon.json <<EOF
        {
          "storage-driver": "overlay2",
          "log-driver": "json-file",
          "log-opts": {"max-size": "10m", "max-file": "3"},
          "insecure-registries": [
            "${MASTER_IP}:30001",
            "quay.io",
            "ghcr.io",
            "registry.k8s.io"
          ]
        }
EOF
            RESTART_DOCKER=1
          fi
          [ "$RESTART_DOCKER" -eq 1 ] && systemctl restart docker || true
          transition_state "docker_installed"

          # Wait for Docker to be fully ready
          echo "Waiting for Docker to be ready..."
          for i in $(seq 1 30); do
            if docker info >/dev/null 2>&1; then
              echo "Docker is ready"
              break
            fi
            sleep 2
          done

          if ! command -v k3s >/dev/null 2>&1; then
            echo "Installing K3s ${K3S_VERSION}..."
            IFACE=$(get_iface "${MASTER_IP}")
            echo "Detected interface (for reference): ${IFACE}"

            K3S_INSTALLED=0
            for attempt in 1 2 3
            do
              echo "K3s install attempt $attempt/3"
              if curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}"                 INSTALL_K3S_EXEC="server                   --write-kubeconfig-mode 644                   --node-name devops-1                   --node-ip ${MASTER_IP}                   --advertise-address ${MASTER_IP}                   --tls-san ${MASTER_IP},127.0.0.1                   --node-external-ip ${MASTER_IP}                   --flannel-backend=vxlan                   --cluster-cidr=10.42.0.0/16                   --service-cidr=10.43.0.0/16                   --disable traefik                   --disable-network-policy" sh -; then
                K3S_INSTALLED=1
                break
              fi
              echo "K3s attempt $attempt failed, retrying in 15s..."
              sleep 15
            done
            [ "$K3S_INSTALLED" -eq 0 ] && { echo "ERROR: K3s install failed after 3 attempts"; exit 1; }
            sleep 15
          fi
          systemctl enable k3s || true
          systemctl start k3s || true
          transition_state "k3s_installed"

          echo "Allowing flannel to stabilize..."
          sleep 40
          wait_for check_k3s_service "k3s service" 120
          wait_for check_api_ready "API /readyz" 180

          echo "Waiting for node devops-1 to register and become Ready..."
          for i in $(seq 1 300); do
            echo "Node registration check $i/300"
            kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide 2>/dev/null || true
            journalctl -u k3s --no-pager | tail -40
            if check_node_registered; then
              echo "Node devops-1 is Ready!"
              break
            fi
            sleep 6
          done
          wait_for check_node_registered "node devops-1 Ready" 300 || echo "WARNING: Continuing despite delay"

          transition_state "node_registered"
          transition_state "node_ready"
          transition_state "cluster_ready"

          mkdir -p /vagrant
          if [ ! -f "$TOKEN_PATH" ]; then
            cp /var/lib/rancher/k3s/server/node-token "$TOKEN_PATH"
            chmod 644 "$TOKEN_PATH"
          fi
          touch "$CLUSTER_READY"

          cat > /vagrant/.cluster_state.json.tmp <<EOF
        {
          "cluster_ready": true,
          "master_ip": "${MASTER_IP}"
        }
EOF
          mv /vagrant/.cluster_state.json.tmp /vagrant/.cluster_state.json

          wait_for check_kubectl_ready "kubectl API ready" 120
          [ -f /usr/local/bin/kubectl ] || ln -sf /var/lib/rancher/k3s/bin/kubectl /usr/local/bin/kubectl

          mkdir -p /etc/bash_completion.d
          kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml completion bash > /etc/bash_completion.d/kubectl 2>/dev/null
          grep -q "source /etc/bash_completion.d/kubectl" /home/vagrant/.bashrc 2>/dev/null || echo 'source /etc/bash_completion.d/kubectl' >> /home/vagrant/.bashrc
          grep -q "alias k=" /home/vagrant/.bashrc 2>/dev/null || echo "alias k='kubectl'" >> /home/vagrant/.bashrc

          command -v helm >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/helm/helm/@@HELM_VERSION@@/scripts/get-helm-3 | DESIRED_VERSION=@@HELM_VERSION@@ bash

          if [ "${FAST_BOOT}" != "true" ]; then
            echo "Installing Ingress NGINX ${INGRESS_NGINX_VERSION}..."
            kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml" || true
            kubectl wait --namespace ingress-nginx --for=condition=Ready pod --selector=app.kubernetes.io/component=controller --timeout=180s 2>/dev/null || true
            check_ingress_running() { kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q Running; }
            wait_for check_ingress_running "Ingress NGINX" 180 || true
            transition_state "ingress_installed"
          fi

          if [ "${FAST_BOOT}" != "true" ]; then
            echo "Installing Harbor ${HARBOR_CHART_VERSION}..."
            helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "harbor" || helm repo add harbor https://helm.goharbor.io
            for i in 1 2 3; do
              if helm repo update 2>/dev/null; then break; fi
              sleep 5
            done
            if helm search repo harbor/harbor --versions 2>/dev/null | grep -q "${HARBOR_CHART_VERSION}"; then
              HELM_VERSION_FLAG="--version ${HARBOR_CHART_VERSION}"
            else
              HELM_VERSION_FLAG=""
            fi

            helm uninstall harbor -n harbor 2>/dev/null || true
            kubectl delete namespace harbor --ignore-not-found=true
            sleep 5

            kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -
            mkdir -p /opt/harbor
            cd /opt/harbor
            if [ ! -f harbor.key ]; then
              openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout harbor.key -out harbor.crt -subj "/CN=${MASTER_IP}" -addext "subjectAltName = IP:${MASTER_IP},IP:127.0.0.1"
            fi
            kubectl create secret tls harbor-tls --cert=harbor.crt --key=harbor.key -n harbor --dry-run=client -o yaml | kubectl apply -f -

            cat > /opt/harbor-values.yaml <<EOF
        expose:
          type: nodePort
          tls:
            enabled: true
            certSource: auto
            auto:
              commonName: ${MASTER_IP}
          nodePort:
            ports:
              https:
                nodePort: 30001
        externalURL: https://${MASTER_IP}:30001
        harborAdminPassword: ${HARBOR_PASS}
        persistence:
          enabled: true
          persistentVolumeClaim:
            registry:
              size: 5Gi
        trivy:
          enabled: true
EOF

            helm upgrade --install harbor harbor/harbor ${HELM_VERSION_FLAG} -n harbor -f /opt/harbor-values.yaml --wait --timeout 15m || {
              echo "ERROR: Harbor install failed — rolling back"
              kubectl get pods -n harbor || true
              helm uninstall harbor -n harbor 2>/dev/null || true
              exit 1
            }

            echo "Waiting for Harbor API to be healthy..."
            HARBOR_HEALTHY=false
            for i in $(seq 1 120); do
              if curl -sk --max-time 10 "https://${MASTER_IP}:30001/api/v2.0/health" 2>/dev/null | grep -q '"status":"healthy"'; then
                echo "Harbor API is healthy"
                HARBOR_HEALTHY=true
                break
              fi
              echo " Waiting for Harbor API... ($i/120)"
              sleep 10
            done
            if [ "$HARBOR_HEALTHY" = "false" ]; then
              echo "ERROR: Harbor API failed to become healthy after 120 attempts"
              exit 1
            fi

            echo "Reconfiguring Docker daemon to trust Harbor registry..."
            cat > /etc/docker/daemon.json <<EOF
        {
          "storage-driver": "overlay2",
          "log-driver": "json-file",
          "log-opts": {"max-size": "10m", "max-file": "3"},
          "insecure-registries": [
            "${MASTER_IP}:30001",
            "quay.io",
            "ghcr.io",
            "registry.k8s.io"
          ]
        }
EOF
            systemctl restart docker
            sleep 10
            echo "Docker daemon reconfigured with Harbor registry"

            echo "=========================================="
            echo "Seeding ${HARBOR_PROJECT} project with airgap images"
            echo "=========================================="

            for i in $(seq 1 30); do
              if curl -sk --max-time 5 "https://${MASTER_IP}:30001/v2/" >/dev/null 2>&1; then
                echo "Registry endpoint is reachable"
                break
              fi
              echo " Registry not yet reachable... ($i/30)"
              sleep 5
            done

            echo "Creating Harbor project: ${HARBOR_PROJECT}..."
            PROJECT_READY="false"
            for i in $(seq 1 30); do
              PROJECT_JSON=$(printf '{"project_name":"%s","metadata":{"public":"true"}}' "${HARBOR_PROJECT}")
              HTTP_CODE=$(curl -sk -o /tmp/harbor_create_resp.json -w '%{http_code}'                 -X POST "https://${MASTER_IP}:30001/api/v2.0/projects"                 -u "admin:${HARBOR_PASS}"                 -H "Content-Type: application/json"                 -d "$PROJECT_JSON" || echo "000")
              echo " Attempt $i/30 HTTP $HTTP_CODE"
              if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
                echo "Project ${HARBOR_PROJECT} ready"
                PROJECT_READY="true"
                break
              fi
              sleep 5
            done

            echo "Verifying project exists in API..."
            for i in $(seq 1 30); do
              VERIFY_PROJECT_CODE=$(curl -sk -o /dev/null -w '%{http_code}' -u "admin:${HARBOR_PASS}" "https://${MASTER_IP}:30001/api/v2.0/projects/${HARBOR_PROJECT}" || echo "000")
              if [ "$VERIFY_PROJECT_CODE" = "200" ]; then
                echo "Project verified"
                PROJECT_READY="true"
                break
              fi
              echo " Waiting for project to appear... ($i/30)"
              sleep 5
            done

            if [ "$PROJECT_READY" != "true" ]; then
              echo "ERROR: Harbor project ${HARBOR_PROJECT} was not created or verified; skipping image seeding"
              kubectl get pods -n harbor || true
              exit 1
            fi

            echo "Logging in to Harbor registry..."
            echo "${HARBOR_PASS}" | docker login "${MASTER_IP}:30001" -u admin --password-stdin || {
              echo "WARNING: Docker login failed"
            }

            for img in "${AIRGAP_IMAGES[@]}"; do
              echo "=== Processing: $img ==="
              norm="${img#docker.io/}"
              norm="${norm#registry.k8s.io/}"
              norm="${norm#quay.io/}"
              norm="${norm#ghcr.io/}"
              if [[ "$norm" == *":"* ]]; then
                repo="${norm%:*}"
                tag="${norm##*:}"
              else
                repo="$norm"
                tag="latest"
              fi
              repo="${repo#library/}"
              target="${MASTER_IP}:30001/${HARBOR_PROJECT}/${repo}:${tag}"
              echo " Target: $target"
              repo_api="${repo////%252F}"
              ARTIFACT_CODE=$(curl -sk -o /dev/null -w '%{http_code}' -u "admin:${HARBOR_PASS}"                 "https://${MASTER_IP}:30001/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${repo_api}/artifacts/${tag}" || echo "000")
              if [ "$ARTIFACT_CODE" = "200" ]; then
                echo " SKIP: Already exists in Harbor"
                continue
              fi

              echo " Pulling (up to 10 attempts)..."
              PULL_SUCCESS=false
              for attempt in 1 2 3 4 5 6 7 8 9 10; do
                if docker pull "$img" >/dev/null 2>&1; then
                  PULL_SUCCESS=true
                  break
                fi
                echo " Pull attempt $attempt failed. Retrying in 30 seconds..."
                sleep 30
              done

              if [ "$PULL_SUCCESS" = "false" ]; then
                echo " WARNING: Pull failed for $img after 10 attempts, skipping"
                echo " --- Last error log: ---"
                docker pull "$img" 2>&1 | tail -n 3
                continue
              fi

              echo " Tagging..."
              docker tag "$img" "$target" || {
                echo " WARNING: Tag failed"
                continue
              }

              echo " Pushing..."
              PUSH_SUCCESS=false
              for attempt in 1 2 3; do
                if docker push "$target" >/dev/null 2>&1; then
                  PUSH_SUCCESS=true
                  break
                fi
                echo " Push attempt $attempt failed. Retrying in 10 seconds..."
                sleep 10
              done

              if [ "$PUSH_SUCCESS" = "true" ]; then
                echo " SUCCESS: $target"
              else
                echo " FAILED: $target"
              fi
            done

            echo "=========================================="
            echo "Image seeding complete!"
            echo "=========================================="

            echo "Configuring K3s containerd registry via Python writer..."
            mkdir -p /etc/rancher/k3s

            export MASTER_IP_VAL="${MASTER_IP}"
            export HARBOR_PROJECT_VAL="${HARBOR_PROJECT}"
            export HARBOR_PASS_VAL="${HARBOR_PASS}"

            python3 -c "import sys, textwrap; exec(textwrap.dedent(sys.stdin.read()))" <<'PYEOF'
        import os
        import sys
        import yaml

        master_ip   = os.environ.get('MASTER_IP_VAL', '192.168.121.114')
        harbor_proj = os.environ.get('HARBOR_PROJECT_VAL', 'airgap')
        harbor_pass = os.environ.get('HARBOR_PASS_VAL', 'Harbor12345')

        content = f'''mirrors:
          "docker.io":
            endpoint:
              - "https://{master_ip}:30001"
            rewrite:
              "^rancher/(.*)": "{harbor_proj}/rancher/$1"
              "^library/(.*)": "{harbor_proj}/library/$1"
              "^(.*)": "{harbor_proj}/$1"
          "quay.io":
            endpoint:
              - "https://{master_ip}:30001"
            rewrite:
              "^(.*)": "{harbor_proj}/$1"
          "ghcr.io":
            endpoint:
              - "https://{master_ip}:30001"
            rewrite:
              "^kyverno/(.*)": "{harbor_proj}/kyverno/$1"
              "^(.*)": "{harbor_proj}/$1"
          "registry.k8s.io":
            endpoint:
              - "https://{master_ip}:30001"
            rewrite:
              "^(.*)": "{harbor_proj}/$1"
          "{master_ip}:30001":
            endpoint:
              - "https://{master_ip}:30001"

        configs:
          "{master_ip}:30001":
            tls:
              insecure_skip_verify: true
            auth:
              username: admin
              password: {harbor_pass}
        '''

        with open('/etc/rancher/k3s/registries.yaml', 'w') as f:
            f.write(content)

        # Validate YAML
        data = yaml.safe_load(content)
        print('VALID YAML - mirrors:', list(data.get('mirrors', {}).keys()))
        sys.exit(0)
PYEOF

            if [ $? -eq 0 ]; then
              echo "Registries.yaml generated and validated successfully"
            else
              echo "ERROR: Failed to generate valid registries.yaml"
              exit 1
            fi

            echo "=== Final registries.yaml ==="
            cat /etc/rancher/k3s/registries.yaml
            echo "============================="

            systemctl restart k3s
            sleep 10
            echo "K3s registry configuration applied with clean YAML"

            echo "=========================================="
            echo "Docker cache mode: ${CACHE_MODE} -> STRICT ZERO (No local images)"
            echo "=========================================="

            docker image prune -a -f 2>/dev/null || true
            docker builder prune -a -f 2>/dev/null || true
            docker system prune -a -f 2>/dev/null || true

            if [ "${CACHE_MODE}" = "zero" ]; then
                echo "Removing ALL images from Docker (including Harbor ones)"
                docker images -q | xargs -r docker rmi -f 2>/dev/null || true
                docker images -q | xargs -r docker rmi -f 2>/dev/null || true
                echo "Docker is now completely clean. No images stored locally."
                echo "All pulls will go through Harbor."
            else
                echo "Warning: CACHE_MODE is not 'zero'. Using safe cleanup."
            fi

            echo "=========================================="
            echo "Final docker images:"
            docker images
            echo "=========================================="

            echo "Creating Kubernetes secret for Harbor registry pull access..."
            kubectl delete secret harbor-secret --ignore-not-found=true
            kubectl create secret docker-registry harbor-secret               --docker-server="${MASTER_IP}:30001"               --docker-username="admin"               --docker-password="${HARBOR_PASS}"               --docker-email="admin@example.com"               --namespace=default
            kubectl patch serviceaccount default -n default -p '{"imagePullSecrets": [{"name": "harbor-secret"}]}'
            echo "Harbor registry secret 'harbor-secret' created and configured for default service account"

            echo "Running final test: Can K3s pull directly from Harbor?"
            kubectl delete pod test-busybox --ignore-not-found=true --grace-period=1 2>/dev/null || true
            sleep 2
            kubectl run test-busybox --image=${MASTER_IP}:30001/${HARBOR_PROJECT}/busybox:1.36 --command -- sleep 10

            if kubectl wait --for=condition=Ready pod/test-busybox --timeout=60s 2>/dev/null; then
                echo "SUCCESS: K3s successfully pulled image from Harbor!"
                kubectl delete pod test-busybox --ignore-not-found=true --grace-period=1 2>/dev/null || true
            else
                echo "FAILED: K3s could not pull from Harbor. Check Harbor and registries.yaml"
                kubectl describe pod test-busybox 2>/dev/null || true
                kubectl delete pod test-busybox --ignore-not-found=true --grace-period=1 2>/dev/null || true
            fi

            echo "=========================================="

            transition_state "harbor_installed"
          fi

          grep -q "${MASTER_IP}" /etc/rancher/k3s/k3s.yaml || sed -i "s/127.0.0.1/${MASTER_IP}/g" /etc/rancher/k3s/k3s.yaml
          cp /etc/rancher/k3s/k3s.yaml /vagrant/kubeconfig.yaml
          chmod 644 /vagrant/kubeconfig.yaml

          if [ ! -f /home/vagrant/.ssh/id_rsa ]; then
            ssh-keygen -t rsa -b 2048 -f /home/vagrant/.ssh/id_rsa -N ""
            cp /home/vagrant/.ssh/id_rsa.pub /vagrant/ansible_key.pub
          fi

          transition_state "base_complete"
          echo "=================================================="
          echo "BASE LAB READY (Profile: ${LAB_PROFILE})"
          echo "Provider: ${PROVIDER}"
          echo "FAST_BOOT: ${FAST_BOOT}"
          echo "CACHE_MODE: ${CACHE_MODE}"
          echo "Harbor: https://${MASTER_IP}:30001 (admin / ${HARBOR_PASS})"
          echo "Harbor Project: ${HARBOR_PROJECT}"
          echo "=================================================="

          jobs -p | xargs -r kill 2>/dev/null || true
          sync
          echo "Provisioning complete - exiting cleanly"
          exit 0

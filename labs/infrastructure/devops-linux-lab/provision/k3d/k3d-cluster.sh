# shellcheck shell=bash
          set -euo pipefail

          K3D_VERSION="${K3D_VERSION:-v5.7.5}"
          KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.0}"
          FAST_BOOT="${FAST_BOOT:-false}"
          MARKER_FILE="/var/lib/k3d_installed"

          if [ -f "$MARKER_FILE" ] && [ "$FAST_BOOT" = "true" ]; then
            echo "K3d already installed, skipping (FAST_BOOT=true)"
            exit 0
          fi

          echo "=========================================="
          echo "INSTALLING K3D (K3s in Docker)"
          echo "=========================================="

          if ! command -v kubectl >/dev/null 2>&1; then
            echo "Installing kubectl ${KUBECTL_VERSION}..."
            curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
            chmod +x /usr/local/bin/kubectl
            echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
          fi

          echo "Installing k3d ${K3D_VERSION}..."
          curl -fsSL "https://raw.githubusercontent.com/k3d-io/k3d/${K3D_VERSION}/install.sh" | TAG=${K3D_VERSION} bash

          if ! command -v helm >/dev/null 2>&1; then
            echo "Installing helm..."
            curl -fsSL https://raw.githubusercontent.com/helm/helm/@@HELM_VERSION@@/scripts/get-helm-3 | DESIRED_VERSION=@@HELM_VERSION@@ bash
          fi

          mkdir -p /opt/k3d
          cat > /opt/k3d/config.yaml <<'EOF'
        apiVersion: k3d.io/v1alpha5
        kind: Simple
        metadata:
          name: lab
        servers: 1
        agents: 2
        ports:
          - port: 8080:80@loadbalancer
          - port: 8443:443@loadbalancer
        options:
          k3d:
            wait: true
            timeout: 60s
          k3s:
            extraArgs:
              - arg: --disable=traefik
                nodeFilters:
                  - server:*
EOF

          echo ""
          echo "Creating K3d cluster automatically..."
          echo "=========================================="

          k3d cluster delete lab 2>/dev/null || true

          if k3d cluster create lab --config /opt/k3d/config.yaml; then
            echo "K3d cluster 'lab' created successfully!"
            mkdir -p /home/vagrant/.kube
            k3d kubeconfig get lab > /home/vagrant/.kube/config
            chown -R vagrant:vagrant /home/vagrant/.kube

            echo ""
            echo "Cluster status:"
            kubectl cluster-info
            kubectl get nodes

            cat >> /home/vagrant/.bashrc <<'EOF'
        # K3d aliases
        alias k3d-kill='k3d cluster delete lab'
        alias k3d-restart='k3d cluster delete lab && k3d cluster create lab --config /opt/k3d/config.yaml'
        alias k3d-status='kubectl get nodes && kubectl get pods -A'
EOF
          else
            echo "ERROR: K3d cluster creation failed"
            exit 1
          fi

          touch "$MARKER_FILE"
          echo ""
          echo "=========================================="
          echo "K3d installed and cluster running!"
          echo ""
          echo "Access the K3d cluster:"
          echo "  kubectl get nodes"
          echo "  kubectl get pods -A"
          echo "=========================================="

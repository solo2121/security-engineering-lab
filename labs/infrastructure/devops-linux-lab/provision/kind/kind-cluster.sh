# shellcheck shell=bash
          set -euo pipefail

          KIND_VERSION="${KIND_VERSION:-v0.24.0}"
          KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.0}"
          FAST_BOOT="${FAST_BOOT:-false}"
          MARKER_FILE="/var/lib/kind_installed"

          if [ -f "$MARKER_FILE" ] && [ "$FAST_BOOT" = "true" ]; then
            echo "Kind already installed, skipping (FAST_BOOT=true)"
            exit 0
          fi

          echo "=========================================="
          echo "INSTALLING KIND (Kubernetes in Docker)"
          echo "=========================================="

          if ! command -v kubectl >/dev/null 2>&1; then
            echo "Installing kubectl ${KUBECTL_VERSION}..."
            curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
            chmod +x /usr/local/bin/kubectl
            echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
          fi

          echo "Installing kind ${KIND_VERSION}..."
          curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" -o /usr/local/bin/kind
          chmod +x /usr/local/bin/kind

          mkdir -p /opt/kind
          cat > /opt/kind/config.yaml <<'EOF'
        kind: Cluster
        apiVersion: kind.x-k8s.io/v1alpha4
        nodes:
        - role: control-plane
        - role: worker
        - role: worker
        networking:
          apiServerAddress: "0.0.0.0"
          apiServerPort: 6443
EOF

          echo ""
          echo "Creating Kind cluster automatically..."
          echo "=========================================="

          kind delete cluster --name lab 2>/dev/null || true

          if kind create cluster --config /opt/kind/config.yaml --name lab; then
            echo "Kind cluster 'lab' created successfully!"
            mkdir -p /home/vagrant/.kube
            kind get kubeconfig --name lab > /home/vagrant/.kube/config
            chown -R vagrant:vagrant /home/vagrant/.kube

            echo ""
            echo "Cluster status:"
            kubectl cluster-info
            kubectl get nodes

            cat >> /home/vagrant/.bashrc <<'EOF'
        # Kind aliases
        alias kind-kill='kind delete cluster --name lab'
        alias kind-restart='kind delete cluster --name lab && kind create cluster --config /opt/kind/config.yaml --name lab'
        alias kind-status='kubectl get nodes && kubectl get pods -A'
EOF
          else
            echo "ERROR: Kind cluster creation failed"
            exit 1
          fi

          touch "$MARKER_FILE"
          echo ""
          echo "=========================================="
          echo "Kind installed and cluster running!"
          echo ""
          echo "Access the Kind cluster:"
          echo "  kubectl get nodes"
          echo "  kubectl get pods -A"
          echo "=========================================="

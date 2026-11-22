# shellcheck shell=bash
          if [ "${DEBUG:-false}" = "true" ]; then set -x; fi
          set -euo pipefail

          MASTER_IP="@@CFG_IP@@"
          ARGOCD_VERSION="@@ARGOCD_VERSION@@"
          PROMETHEUS_VERSION="@@PROMETHEUS_VERSION@@"
          FALCO_VERSION="@@FALCO_VERSION@@"
          KYVERNO_VERSION="@@KYVERNO_VERSION@@"
          CERT_MANAGER_VERSION="@@CERT_MANAGER_VERSION@@"
          TERRAFORM_VERSION="@@TERRAFORM_VERSION@@"
          OPENTOFU_VERSION="@@OPENTOFU_VERSION@@"
          FAST_BOOT="@@FAST_BOOT@@"

          # ========== TERRAFORM INSTALLATION ==========
          TERRAFORM_MARKER="/var/lib/terraform_installed"

          if [ ! -f "$TERRAFORM_MARKER" ] || [ "${FAST_BOOT}" != "true" ]; then
            echo "=========================================="
            echo "INSTALLING TERRAFORM ${TERRAFORM_VERSION}"
            echo "=========================================="

            rm -f /usr/local/bin/terraform
            TEMP_DIR=$(mktemp -d)
            cd "$TEMP_DIR"

            ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
            echo "Detected architecture: ${ARCH}"

            curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -o terraform.zip
            apt-get install -y unzip 2>/dev/null || dnf install -y unzip 2>/dev/null || zypper install -y unzip 2>/dev/null || true
            unzip -q terraform.zip
            mv terraform /usr/local/bin/
            chmod +x /usr/local/bin/terraform

            if command -v terraform >/dev/null 2>&1; then
              TERRAFORM_INSTALLED_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1)
              echo "Terraform installed successfully: ${TERRAFORM_INSTALLED_VERSION}"
              terraform -install-autocomplete 2>/dev/null || true
              touch "$TERRAFORM_MARKER"
            else
              echo "ERROR: Terraform installation failed"
              exit 1
            fi

            cd /
            rm -rf "$TEMP_DIR"

            echo "=========================================="
          else
            echo "Terraform already installed, skipping (FAST_BOOT=true)"
          fi

          # ========== OPENTOFU INSTALLATION ==========
          OPENTOFU_MARKER="/var/lib/opentofu_installed"

          if [ ! -f "$OPENTOFU_MARKER" ] || [ "${FAST_BOOT}" != "true" ]; then
            echo "=========================================="
            echo "INSTALLING OPENTOFU ${OPENTOFU_VERSION}"
            echo "=========================================="

            rm -f /usr/local/bin/tofu
            TEMP_DIR=$(mktemp -d)
            cd "$TEMP_DIR"

            ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
            echo "Detected architecture: ${ARCH}"

            curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${ARCH}.zip" -o tofu.zip
            apt-get install -y unzip 2>/dev/null || dnf install -y unzip 2>/dev/null || zypper install -y unzip 2>/dev/null || true
            unzip -q tofu.zip
            mv tofu /usr/local/bin/
            chmod +x /usr/local/bin/tofu

            if command -v tofu >/dev/null 2>&1; then
              TOFU_VERSION=$(tofu version -json 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || tofu version | head -1)
              echo "OpenTofu installed successfully: ${TOFU_VERSION}"
              tofu -install-autocomplete 2>/dev/null || true
              touch "$OPENTOFU_MARKER"
            else
              echo "ERROR: OpenTofu installation failed"
              exit 1
            fi

            cd /
            rm -rf "$TEMP_DIR"

            echo "=========================================="
          else
            echo "OpenTofu already installed, skipping (FAST_BOOT=true)"
          fi

          export PATH=$PATH:/usr/local/bin
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

          ENTERPRISE_MARKER="/var/lib/enterprise_tools_installed"
          CERTS_MARKER="/var/lib/cert_manager_installed"
          KYVERNO_MARKER="/var/lib/kyverno_installed"
          FALCO_MARKER="/var/lib/falco_installed"
          PROMETHEUS_MARKER="/var/lib/prometheus_installed"
          ARGOCD_MARKER="/var/lib/argocd_installed"

          if [ -f "$ENTERPRISE_MARKER" ]; then
            echo "Enterprise tools already installed (legacy marker), skipping"
            exit 0
          fi

          echo "=========================================="
          echo "INSTALLING ENTERPRISE DEVSECOPS TOOLS"
          echo "=========================================="

          if [ "${FAST_BOOT}" != "true" ]; then

            # ========== CERT-MANAGER ==========
            if [ ! -f "$CERTS_MARKER" ]; then
              echo "Installing cert-manager ${CERT_MANAGER_VERSION}..."
              kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml" || true
              echo "Waiting for cert-manager pods..."
              for i in $(seq 1 40); do
                if kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -q Running; then
                  echo "cert-manager is ready"
                  break
                fi
                if kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -qE "ImagePullBackOff|CrashLoopBackOff|ErrImagePull"; then
                  echo "WARNING: cert-manager pods are in a failed state. Breaking wait loop."
                  break
                fi
                echo " Waiting for cert-manager... ($i/40)"
                sleep 5
              done
              touch "$CERTS_MARKER"
            else
              echo "cert-manager already installed, skipping"
            fi

            # ========== KYVERNO ==========
            if [ ! -f "$KYVERNO_MARKER" ]; then
              echo "Installing Kyverno ${KYVERNO_VERSION}..."
              helm uninstall kyverno -n kyverno 2>/dev/null || true
              kubectl delete namespace kyverno --ignore-not-found=true
              sleep 10

              helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update || true
              helm repo update || true

              INSTALL_SUCCESS=false
              for attempt in 1 2 3; do
                echo "Kyverno install attempt $attempt/3..."
                if helm upgrade --install kyverno kyverno/kyverno                   --namespace kyverno                   --create-namespace                   --version ${KYVERNO_VERSION}                   --set installCRDs=true                   --wait                   --timeout 10m 2>/dev/null; then
                  INSTALL_SUCCESS=true
                  echo "Kyverno installed successfully on attempt $attempt"
                  break
                else
                  echo "Kyverno attempt $attempt failed, waiting 30s before retry..."
                  kubectl delete namespace kyverno --ignore-not-found=true 2>/dev/null || true
                  sleep 30
                fi
              done

              if [ "$INSTALL_SUCCESS" = "false" ]; then
                echo "WARNING: Kyverno install had issues - continuing anyway"
                helm upgrade --install kyverno kyverno/kyverno                   --namespace kyverno                   --create-namespace                   --version ${KYVERNO_VERSION}                   --set installCRDs=true || true
              fi

              echo "Waiting for Kyverno pods..."
              for i in $(seq 1 60); do
                RUNNING_COUNT=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -c Running || echo "0")
                TOTAL_COUNT=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | wc -l || echo "0")
                if [ "$TOTAL_COUNT" -gt 0 ] && [ "$RUNNING_COUNT" -eq "$TOTAL_COUNT" ]; then
                  echo "All Kyverno pods are ready ($RUNNING_COUNT/$TOTAL_COUNT)"
                  break
                fi
                if kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -qE "ImagePullBackOff|CrashLoopBackOff|ErrImagePull"; then
                  echo "WARNING: Kyverno pods are in a failed state. Breaking wait loop."
                  break
                fi
                echo " Waiting for Kyverno... ($i/60) - $RUNNING_COUNT/$TOTAL_COUNT running"
                sleep 10
              done
              touch "$KYVERNO_MARKER"
            else
              echo "Kyverno already installed, skipping"
            fi

            # ========== FALCO ==========
            if [ ! -f "$FALCO_MARKER" ]; then
              echo "Installing Falco ${FALCO_VERSION}..."
              helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update || true
              helm repo update || true
              helm upgrade --install falco falcosecurity/falco                 --namespace falco                 --create-namespace                 --version ${FALCO_VERSION}                 --set falco.jsonOutput=true                 --set falco.fileOutput.enabled=true                 --set falco.fileOutput.json=true                 --wait                 --timeout 10m || echo "WARNING: Falco install had issues"
              touch "$FALCO_MARKER"
            else
              echo "Falco already installed, skipping"
            fi

            # ========== PROMETHEUS + GRAFANA ==========
            if [ ! -f "$PROMETHEUS_MARKER" ]; then
              echo "Installing Prometheus Stack ${PROMETHEUS_VERSION}..."
              kubectl delete svc prometheus-stack-grafana -n monitoring --ignore-not-found=true

              helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update || true
              helm repo update || true

              cat > /tmp/prometheus-values.yaml <<EOF
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
            serviceMonitorSelector: {}
            serviceMonitorNamespaceSelector: {}
        grafana:
          adminPassword: admin
          service:
            type: NodePort
          persistence:
            enabled: true
            size: 1Gi
        alertmanager:
          enabled: true
EOF

              helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack                 --namespace monitoring                 --create-namespace                 --version ${PROMETHEUS_VERSION}                 --values /tmp/prometheus-values.yaml                 --wait                 --timeout 15m || echo "WARNING: Prometheus stack install had issues"

              echo "Waiting for Prometheus and Grafana pods..."
              for i in $(seq 1 60); do
                if kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -q Running; then
                  RUNNING_COUNT=$(kubectl get pods -n monitoring --no-headers | grep -c Running || echo "0")
                  TOTAL_COUNT=$(kubectl get pods -n monitoring --no-headers | wc -l || echo "0")
                  echo " Monitoring pods: $RUNNING_COUNT/$TOTAL_COUNT running... ($i/60)"
                  if [ "$RUNNING_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 5 ]; then
                    echo "All monitoring pods are ready"
                    break
                  fi
                fi
                if kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -qE "ImagePullBackOff|CrashLoopBackOff|ErrImagePull"; then
                  echo "WARNING: Monitoring pods are in a failed state. Breaking wait loop."
                  break
                fi
                sleep 5
              done

              GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-stack-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30002")
              echo "Grafana will be available at: https://${MASTER_IP}:${GRAFANA_PORT} (admin/admin)"
              touch "$PROMETHEUS_MARKER"
            else
              echo "Prometheus stack already installed, skipping"
              GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-stack-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30002")
            fi

            # ========== ARGO CD ==========
            if [ ! -f "$ARGOCD_MARKER" ]; then
              echo "Installing Argo CD ${ARGOCD_VERSION}..."

              helm uninstall argocd -n argocd 2>/dev/null || true
              kubectl delete namespace argocd --ignore-not-found=true
              kubectl delete applications --all -n argocd --ignore-not-found=true --wait=false 2>/dev/null || true
              kubectl delete crd applications.argoproj.io --ignore-not-found=true --wait=false 2>/dev/null || true
              kubectl delete crd appprojects.argoproj.io --ignore-not-found=true --wait=false 2>/dev/null || true
              kubectl delete crd applicationsets.argoproj.io --ignore-not-found=true --wait=false 2>/dev/null || true

              sleep 30

              helm repo add argo https://argoproj.github.io/argo-helm --force-update || true
              helm repo update || true

              helm upgrade --install argocd argo/argo-cd                 --namespace argocd                 --create-namespace                 --version ${ARGOCD_VERSION}                 --set server.service.type=NodePort                 --set server.service.servicePortHttp=80                 --set server.service.servicePortHttps=443                 --set server.service.nodePortHttp=30003                 --set server.service.nodePortHttps=30004                 --wait                 --timeout 10m || echo "WARNING: Argo CD install had issues"

              echo "Waiting for Argo CD pods..."
              for i in $(seq 1 60); do
                if kubectl get pods -n argocd --no-headers 2>/dev/null | grep -q Running; then
                  RUNNING_COUNT=$(kubectl get pods -n argocd --no-headers | grep -c Running || echo "0")
                  TOTAL_COUNT=$(kubectl get pods -n argocd --no-headers | wc -l || echo "0")
                  echo " Argo CD pods: $RUNNING_COUNT/$TOTAL_COUNT running... ($i/60)"
                  if [ "$RUNNING_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 5 ]; then
                    echo "All Argo CD pods are ready"
                    break
                  fi
                fi
                if kubectl get pods -n argocd --no-headers 2>/dev/null | grep -qE "ImagePullBackOff|CrashLoopBackOff|ErrImagePull"; then
                  echo "WARNING: Argo CD pods are in a failed state. Breaking wait loop."
                  break
                fi
                sleep 5
              done

              echo ""
              echo "=========================================="
              echo "Argo CD initial admin password:"
              kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Password extraction failed, check manually"
              echo ""
              echo "=========================================="
              touch "$ARGOCD_MARKER"
            else
              echo "Argo CD already installed, skipping"
            fi

            # ========== DAY-2 TOOLS ==========
            echo "Installing kubectx, kubens, stern, and k9s..."
            git clone https://github.com/ahmetb/kubectx /opt/kubectx 2>/dev/null || true
            ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx || true
            ln -sf /opt/kubectx/kubens /usr/local/bin/kubens || true
            curl -sSLo /usr/local/bin/stern "https://github.com/stern/stern/releases/download/v1.28.0/stern_linux_amd64" && chmod +x /usr/local/bin/stern || echo "WARNING: stern download failed"
            curl -sSLo /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/download/v0.32.5/k9s_Linux_amd64.tar.gz" && tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s && chmod +x /usr/local/bin/k9s || echo "WARNING: k9s download failed"

            echo "=========================================="
            echo "ENTERPRISE TOOLS INSTALLATION COMPLETE"
            echo "=========================================="
            echo ""
            echo "cert-manager: TLS certificate management"
            echo "Kyverno: Policy enforcement"
            echo "Falco: Runtime security"
            echo "Prometheus: Metrics collection"
            echo "Grafana: https://${MASTER_IP}:${GRAFANA_PORT} (admin/admin)"
            echo "Argo CD: https://${MASTER_IP}:30003"
            echo "Terraform: $(terraform version | head -1)"
            echo "OpenTofu: $(tofu version | head -1)"
            echo "=========================================="
          fi

          touch "$ENTERPRISE_MARKER"

# Air-gap images
# Container images pre-loaded into Harbor.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# AIRGAP IMAGES
# =============================================================================
AIRGAP_IMAGES = [
  "docker.io/rancher/mirrored-pause:3.6",
  "docker.io/rancher/mirrored-coredns-coredns:1.11.1",
  "docker.io/rancher/local-path-provisioner:v0.0.30",
  "registry.k8s.io/ingress-nginx/controller:v1.11.3",
  "registry.k8s.io/metrics-server/metrics-server:v0.7.1",
  "docker.io/aquasec/trivy:0.57.1",
  "docker.io/falcosecurity/falco:0.39.2",
  "quay.io/argoproj/argocd:v2.13.0",
  "docker.io/prom/prometheus:v3.0.0",
  "docker.io/grafana/grafana:11.2.0",
  "docker.io/library/postgres:16",
  "docker.io/library/redis:7",
  "docker.io/library/nginx:alpine",
  "docker.io/library/busybox:1.36",
  "docker.io/library/alpine:3.20",
  "quay.io/jetstack/cert-manager-cainjector:v1.16.2",
  "quay.io/jetstack/cert-manager-controller:v1.16.2",
  "quay.io/jetstack/cert-manager-webhook:v1.16.2",
  "quay.io/jetstack/cert-manager-acmesolver:v1.16.2",
  "ghcr.io/kyverno/kyverno:v1.13.2",
  "ghcr.io/kyverno/kyvernopre:v1.13.2",
  "ghcr.io/kyverno/background-controller:v1.13.2",
  "ghcr.io/kyverno/cleanup-controller:v1.13.2",
  "ghcr.io/kyverno/reports-controller:v1.13.2",
  "quay.io/prometheus-operator/prometheus-operator:v0.76.2",
  "quay.io/prometheus/node-exporter:v1.8.2",
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0",
  "quay.io/prometheus/alertmanager:v0.27.0",
  "quay.io/prometheus/pushgateway:v1.8.0",
  "docker.io/falcosecurity/falco-driver-loader:latest",
  "docker.io/grafana/loki:3.2.1",
  "docker.io/grafana/promtail:3.2.1",
  "quay.io/argoproj/argocd-applicationset:v0.4.1",
  "quay.io/argoproj/argo-rollouts:v1.7.2",
  "ghcr.io/dexidp/dex:v2.41.1",
  "docker.io/library/redis:7.2.5-alpine",
  "docker.io/library/haproxy:2.8-alpine",
].freeze

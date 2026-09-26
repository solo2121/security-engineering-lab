# Complete DevOps Platform Guide: Infrastructure to GitOps
## Vagrant + Kubernetes + Terraform + Ansible + ArgoCD + Observability

> **Standalone tutorial, not this repo's lab.** This guide has you hand-write
> your own single-VM Vagrantfile and set up k3d from scratch to learn the
> concepts end-to-end. It is intentionally independent of
> `labs/infrastructure/devops-linux-lab/`, which uses k3s, Harbor, and Argo CD
> across its own multi-VM Vagrantfile and Ansible roles — see that lab's
> [README](../../../labs/infrastructure/devops-linux-lab/README.md) if you
> want to work with the actual repository lab.

---

## Table of Contents

1. [Executive Overview](#executive-overview)
2. [Architecture](#architecture)
3. [Prerequisites & System Requirements](#prerequisites--system-requirements)
4. [Phase 0: Local Lab Setup](#phase-0-local-lab-setup)
5. [Phase 1: Docker & Container Fundamentals](#phase-1-docker--container-fundamentals)
6. [Phase 2: Kubernetes Setup (k3d)](#phase-2-kubernetes-setup-k3d)
7. [Phase 3: Infrastructure as Code (Terraform)](#phase-3-infrastructure-as-code-terraform)
8. [Phase 4: Configuration Management (Ansible)](#phase-4-configuration-management-ansible)
9. [Phase 5: Application Packaging (Helm)](#phase-5-application-packaging-helm)
10. [Phase 6: GitOps & Continuous Deployment (ArgoCD)](#phase-6-gitops--continuous-deployment-argocd)
11. [Phase 7: Security & Scanning](#phase-7-security--scanning)
12. [Phase 8: Observability Stack](#phase-8-observability-stack)
13. [Phase 9: Secret Management](#phase-9-secret-management)
14. [Phase 10: Advanced Deployments](#phase-10-advanced-deployments)
15. [Phase 11: Chaos Engineering & Resilience](#phase-11-chaos-engineering--resilience)
16. [Complete CI/CD Pipeline](#complete-cicd-pipeline)
17. [Troubleshooting & Best Practices](#troubleshooting--best-practices)

---

## Executive Overview

This guide builds a **production-grade DevOps platform** suitable for learning, testing, and portfolio development. It integrates:

- **Vagrant + KVM/QEMU** → Reproducible VM infrastructure
- **Docker** → Containerization runtime
- **Kubernetes (k3d)** → Container orchestration
- **Terraform** → Infrastructure as Code provisioning
- **Ansible** → Configuration management & automation
- **Helm** → Kubernetes application packaging
- **ArgoCD** → GitOps continuous deployment
- **Prometheus + Grafana + Loki** → Observability stack
- **Trivy + Cosign** → Security scanning & image signing
- **Sealed Secrets / SOPS** → Secret encryption
- **Kyverno** → Policy as Code
- **Chaos Mesh** → Resilience testing

**Why consolidated into one guide?**
- Single source of truth
- Seamless progression from basics to production concepts
- Elimination of redundancy
- Clear, professional structure
- Easily adjustable for different hardware profiles

---

## Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Developer Workflow                           │
│  (Git Push → Webhook → CI/CD → Deployment)                     │
└────────────────────┬────────────────────────────────────────────┘
                     │
        ┌────────────▼───────────────┐
        │    GitHub / GitLab         │
        │  (Source of Truth)         │
        └────────────┬───────────────┘
                     │
        ┌────────────▼──────────────────┐
        │  CI Pipeline (GitHub Actions) │
        │  • Build                      │
        │  • Test                       │
        │  • Scan (Trivy)              │
        │  • Sign (Cosign)             │
        │  • Push Image                 │
        └────────────┬──────────────────┘
                     │
        ┌────────────▼──────────────────────────┐
        │       ArgoCD (GitOps)                 │
        │  Watches GitOps Repo → Syncs         │
        └────────────┬──────────────────────────┘
                     │
        ┌────────────▼─────────────────────────────────────┐
        │    Kubernetes Cluster (k3d)                      │
        │  ┌──────────────────────────────────────────┐   │
        │  │ Namespaces: dev / staging / prod         │   │
        │  │ ┌────────────────────────────────┐       │   │
        │  │ │ Applications (Helm-managed)    │       │   │
        │  │ │ • Deployments                  │       │   │
        │  │ │ • Services                     │       │   │
        │  │ │ • ConfigMaps & Secrets         │       │   │
        │  │ └────────────────────────────────┘       │   │
        │  │ ┌────────────────────────────────┐       │   │
        │  │ │ Observability                  │       │   │
        │  │ │ • Prometheus (metrics)         │       │   │
        │  │ │ • Grafana (dashboards)         │       │   │
        │  │ │ • Loki (logs)                  │       │   │
        │  │ └────────────────────────────────┘       │   │
        │  │ ┌────────────────────────────────┐       │   │
        │  │ │ Security                       │       │   │
        │  │ │ • Kyverno (policies)           │       │   │
        │  │ │ • Sealed Secrets               │       │   │
        │  │ │ • RBAC                         │       │   │
        │  │ └────────────────────────────────┘       │   │
        │  └──────────────────────────────────────────┘   │
        └──────────────────────────────────────────────────┘
                     │
        ┌────────────▼──────────────────┐
        │   Monitoring & Alerting       │
        │  • Prometheus Alerts          │
        │  • Grafana Notifications      │
        │  • PagerDuty Integration      │
        └───────────────────────────────┘
```

### Network & Compute Topology

```
Host Machine (Linux)
  │
  ├─► Vagrant VM (8GB RAM, 4 CPU)
  │     │
  │     ├─► Docker Daemon
  │     │
  │     ├─► k3d Cluster (Kubernetes)
  │     │     ├─ Control Plane (1)
  │     │     └─ Worker Nodes (2+)
  │     │
  │     ├─► Terraform (provisioning)
  │     ├─► Ansible (configuration)
  │     ├─► kubectl (cluster management)
  │     ├─► Helm (app packaging)
  │     └─► ArgoCD CLI
  │
  ├─► Jenkins (Optional, on host or VM)
  ├─► Prometheus (Monitoring)
  └─► Grafana (Dashboards)
```

---

## Prerequisites & System Requirements

### Hardware

| Profile | CPU | RAM | Storage | Use Case |
|---------|-----|-----|---------|----------|
| **Baseline** | 4 | 8 GB | 20 GB | Docker, kubectl |
| **Standard** | 4-6 | 12-16 GB | 30 GB | Helm, Terraform, Ansible, DevSecOps |
| **Full** | 8+ | 16-32 GB | 50+ GB | All features + Prometheus + ArgoCD |

### Software Requirements

```bash
# Host system (Ubuntu 22.04 LTS+)
- KVM/QEMU enabled in BIOS
- Vagrant installed
- vagrant-libvirt plugin
- git, curl, wget

# Inside Vagrant VM
- Docker
- kubectl
- Helm
- Terraform
- Ansible
- k3d
- Docker Compose
```

### Recommended Reading

- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [Terraform Best Practices](https://www.terraform.io/docs/backends/index.html)
- [Ansible Playbook Guide](https://docs.ansible.com/ansible/latest/playbook_guide/index.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

## Phase 0: Local Lab Setup

### 0.1 Host System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install KVM and virtualization tools
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils virtinst virt-manager

# Install Vagrant
sudo apt install -y vagrant

# Install vagrant-libvirt plugin
vagrant plugin install vagrant-libvirt

# Add current user to libvirt group (allows non-root VMs)
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Enable libvirtd service
sudo systemctl enable --now libvirtd

# Verify installation
virsh list --all
echo "KVM is ready!" || echo "KVM setup failed"
```

### 0.2 Production-Grade Vagrantfile

Create `Vagrantfile` in your lab directory:

```ruby
ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'

Vagrant.configure("2") do |config|
  # Use Ubuntu 24.04 LTS
  config.vm.box = "generic/ubuntu2404"
  
  # Hostname
  config.vm.hostname = "devops-lab"
  
  # Network configuration
  config.vm.network "private_network", type: "dhcp"
  
  # Port forwarding for services
  config.vm.network "forwarded_port", guest: 8080, host: 8080   # Jenkins
  config.vm.network "forwarded_port", guest: 3000, host: 3000   # Grafana
  config.vm.network "forwarded_port", guest: 9090, host: 9090   # Prometheus
  config.vm.network "forwarded_port", guest: 6443, host: 6443   # Kubernetes API
  
  # Synced folder for project files
  config.vm.synced_folder ".", "/home/vagrant/lab", type: "nfs",
    nfs_version: 4, nfs_udp: false
  
  # KVM/libvirt provider configuration
  config.vm.provider "libvirt" do |v|
    v.memory = 8192  # 8 GB RAM
    v.cpus = 4
    v.cpu_mode = "host-passthrough"
    v.nested = true
    v.volume_cache = "unsafe"  # Better performance for labs
  end
  
  # Provision with basic tools and Docker
  config.vm.provision "shell", inline: <<-SHELL
    set -e

    echo "==> Installing system dependencies..."
    apt-get update
    apt-get install -y \
      curl wget git ca-certificates gnupg lsb-release \
      python3 python3-pip python3-venv \
      jq yq htop build-essential

    echo "==> Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
      tee /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable --now docker
    usermod -aG docker vagrant

    echo "==> Vagrant provisioning complete!"
  SHELL
end
```

### 0.3 Launch the Lab Environment

```bash
# Create lab directory
mkdir -p ~/devops-lab && cd ~/devops-lab

# Copy the Vagrantfile above to this directory

# Start the VM
vagrant up

# SSH into the VM
vagrant ssh devops-lab
```

---

## Phase 1: Docker & Container Fundamentals

### 1.1 Docker Installation (Inside Vagrant VM)

The Vagrantfile above includes Docker, but verify it's working:

```bash
docker --version
docker run hello-world
```

### 1.2 Basic Docker Operations

**Build a Simple Container:**

Create `Dockerfile`:

```dockerfile
FROM ubuntu:22.04

WORKDIR /app

RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    pip3 install flask

COPY requirements.txt .
RUN pip3 install -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python3", "app.py"]
```

Create `app.py`:

```python
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "environment": os.getenv("APP_ENV", "dev")})

@app.route('/api/version')
def version():
    return jsonify({"version": "1.0.0"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
```

Create `requirements.txt`:

```
Flask==2.3.0
```

**Build and Run:**

```bash
# Build the image
docker build -t devops-app:1.0.0 .

# Run the container
docker run -d \
  --name devops-app \
  -p 5000:5000 \
  -e APP_ENV=production \
  devops-app:1.0.0

# Test the application
curl http://localhost:5000/health

# View logs
docker logs devops-app

# Stop and remove
docker stop devops-app
docker rm devops-app
```

### 1.3 Docker Compose for Multi-Container Apps

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  app:
    build: .
    container_name: devops-app
    ports:
      - "5000:5000"
    environment:
      - APP_ENV=production
      - DB_HOST=postgres
      - DB_USER=appuser
      - DB_PASSWORD=secretpass
    depends_on:
      - postgres
    networks:
      - devops-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  postgres:
    image: postgres:15-alpine
    container_name: devops-postgres
    environment:
      - POSTGRES_DB=appdb
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=secretpass
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - devops-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser"]
      interval: 10s
      timeout: 3s
      retries: 3

networks:
  devops-network:
    driver: bridge

volumes:
  postgres_data:
```

**Run the Stack:**

```bash
docker-compose up -d
docker-compose ps
docker-compose logs -f app
docker-compose down
```

### 1.4 Docker Best Practices

```dockerfile
# Multi-stage builds reduce image size
FROM golang:1.20 AS builder
WORKDIR /app
COPY . .
RUN go build -o myapp .

FROM alpine:3.18
WORKDIR /app
COPY --from=builder /app/myapp .
EXPOSE 8080
CMD ["./myapp"]
```

---

## Phase 2: Kubernetes Setup (k3d)

### 2.1 Install k3d

```bash
# Download and install k3d
# Download, inspect, then run — piping curl directly to a shell executes
# whatever that URL returns with your current privileges, with no chance
# to review it first. Downloading a script doesn't make it trustworthy;
# read it before running it.
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh -o /tmp/k3d-install.sh
less /tmp/k3d-install.sh   # inspect before running
chmod +x /tmp/k3d-install.sh
bash /tmp/k3d-install.sh
rm -f /tmp/k3d-install.sh

# Verify installation
k3d version
```

### 2.2 Create a Kubernetes Cluster

```bash
# Create a cluster with optimized settings for the lab
k3d cluster create devops-cluster \
  --servers 1 \
  --agents 2 \
  --api-port 6443 \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0" \
  --volume /tmp/k3d-storage:/tmp/storage

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

### 2.3 Create Namespaces

```bash
# Create namespaces for different environments
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace prod
kubectl create namespace monitoring
kubectl create namespace security

# Verify
kubectl get namespaces
```

### 2.4 Deploy Your First Application

Create `deployment.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: dev
data:
  APP_ENV: "development"
  LOG_LEVEL: "info"

---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: dev
type: Opaque
stringData:
  DB_PASSWORD: "secure-password-123"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app
  namespace: dev
  labels:
    app: devops-app
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: devops-app
  template:
    metadata:
      labels:
        app: devops-app
        version: v1
    spec:
      containers:
      - name: app
        image: devops-app:1.0.0
        imagePullPolicy: Never  # Use local image
        ports:
        - containerPort: 5000
          name: http
        env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: DB_PASSWORD
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: devops-app
  namespace: dev
  labels:
    app: devops-app
spec:
  type: ClusterIP
  selector:
    app: devops-app
  ports:
  - port: 5000
    targetPort: 5000
    protocol: TCP
    name: http

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: devops-app-hpa
  namespace: dev
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: devops-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

**Deploy:**

```bash
# Load local image into k3d
docker build -t devops-app:1.0.0 .
k3d image import devops-app:1.0.0 -c devops-cluster

# Deploy
kubectl apply -f deployment.yaml

# Verify
kubectl get all -n dev
kubectl logs -f deployment/devops-app -n dev

# Access the app
kubectl port-forward svc/devops-app 5000:5000 -n dev
curl http://localhost:5000/health
```

---

## Phase 3: Infrastructure as Code (Terraform)

### 3.1 Terraform with Kubernetes Provider

Create `terraform/main.tf`:

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Uncomment for remote state (AWS S3, etc.)
  # backend "s3" {
  #   bucket         = "my-terraform-state"
  #   key            = "devops-lab/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Namespace management
resource "kubernetes_namespace" "environments" {
  for_each = toset(["dev", "staging", "prod", "monitoring"])

  metadata {
    name = each.key
    labels = {
      name       = each.key
      managed-by = "terraform"
    }
  }
}

# Network policies for security
resource "kubernetes_network_policy" "prod_isolation" {
  metadata {
    name      = "prod-network-policy"
    namespace = kubernetes_namespace.environments["prod"].metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "frontend"
          }
        }
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "prod"
          }
        }
      }
    }
  }
}
```

Create `terraform/variables.tf`:

```hcl
variable "app_name" {
  description = "Application name"
  type        = string
  default     = "devops-app"
}

variable "replicas" {
  description = "Number of replicas per environment"
  type = map(number)
  default = {
    dev     = 2
    staging = 2
    prod    = 3
  }
}

variable "image_registry" {
  description = "Docker image registry"
  type        = string
  default     = "docker.io"
}
```

Create `terraform/outputs.tf`:

```hcl
output "namespaces" {
  description = "Created Kubernetes namespaces"
  value       = keys(kubernetes_namespace.environments)
}

output "kubeconfig_path" {
  description = "Path to kubeconfig"
  value       = "~/.kube/config"
}
```

**Run Terraform:**

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply configuration
terraform apply -auto-approve

# Verify
kubectl get namespaces
```

---

## Phase 4: Configuration Management (Ansible)

### 4.1 Ansible Playbook Structure

Create `ansible/inventory.ini`:

```ini
[kubernetes_masters]
k3d_master ansible_host=127.0.0.1 ansible_user=vagrant

[kubernetes_workers]
k3d_worker1 ansible_host=127.0.0.1 ansible_user=vagrant
k3d_worker2 ansible_host=127.0.0.1 ansible_user=vagrant

[kubernetes:children]
kubernetes_masters
kubernetes_workers

[all:vars]
ansible_connection=local
kubernetes_version=1.27.0
```

Create `ansible/roles/kubernetes/tasks/main.yml`:

```yaml
---
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600
  become: yes

- name: Install Kubernetes dependencies
  apt:
    name:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg2
      - software-properties-common
    state: present
  become: yes

- name: Add Kubernetes apt key
  apt_key:
    url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    state: present
  become: yes

- name: Add Kubernetes repository
  apt_repository:
    repo: "deb https://apt.kubernetes.io/ kubernetes-xenial main"
    state: present
  become: yes

- name: Install kubelet, kubeadm, kubectl
  apt:
    name:
      - "kubelet={{ kubernetes_version }}-00"
      - "kubeadm={{ kubernetes_version }}-00"
      - "kubectl={{ kubernetes_version }}-00"
    state: present
  become: yes
```

Create `ansible/playbooks/site.yml`:

```yaml
---
- name: Configure Kubernetes cluster
  hosts: kubernetes
  become: yes
  roles:
    - role: kubernetes
      tags: kubernetes

- name: Deploy applications
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Add Helm repository
      helm_repository:
        name: stable
        repo_url: https://charts.helm.sh/stable

    - name: Deploy application stack
      helm:
        name: devops-app
        chart_ref: ./charts/devops-app
        release_namespace: dev
        create_namespace: yes
        values:
          replicas: 3
          image: devops-app:1.0.0
```

**Run Ansible:**

```bash
cd ansible

# Install Ansible
pip3 install ansible

# Run playbook with inventory
ansible-playbook -i inventory.ini playbooks/site.yml

# Or run specific tags
ansible-playbook -i inventory.ini playbooks/site.yml --tags kubernetes
```

---

## Phase 5: Application Packaging (Helm)

### 5.1 Create a Helm Chart

```bash
helm create charts/devops-app
```

Structure:

```
charts/devops-app/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-staging.yaml
├── values-prod.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── hpa.yaml
│   ├── ingress.yaml
│   └── tests/
```

Edit `Chart.yaml`:

```yaml
apiVersion: v2
name: devops-app
description: Complete DevOps application Helm chart
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - devops
  - kubernetes
  - helm
maintainers:
  - name: DevOps Team
    email: devops@example.com
```

Edit `values.yaml`:

```yaml
replicaCount: 2

image:
  repository: devops-app
  pullPolicy: IfNotPresent
  tag: "1.0.0"

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "5000"
  prometheus.io/path: "/metrics"

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

service:
  type: ClusterIP
  port: 5000
  annotations: {}

ingress:
  enabled: false
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: devops-app.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: devops-app-tls
      hosts:
        - devops-app.example.com

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
  targetMemoryUtilizationPercentage: 70

env:
  - name: APP_ENV
    value: "production"
  - name: LOG_LEVEL
    value: "info"

secrets:
  - name: DB_PASSWORD
    value: "changeme"

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Deploy with Helm:**

```bash
# Install
helm install devops-app ./charts/devops-app \
  --namespace dev \
  --create-namespace

# Upgrade with custom values
helm upgrade devops-app ./charts/devops-app \
  --namespace dev \
  -f values-prod.yaml \
  --set replicaCount=5

# List releases
helm list -A

# View deployment
helm status devops-app -n dev
helm get values devops-app -n dev

# Rollback if needed
helm rollback devops-app 1 -n dev
```

---

## Phase 6: GitOps & Continuous Deployment (ArgoCD)

### 6.1 Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 6.2 Access ArgoCD UI

```bash
# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access: https://localhost:8443 (accept self-signed cert)
# Username: admin
# Password: <from above>
```

### 6.3 Create GitOps Repository Structure

In a separate Git repository (e.g., `devops-gitops-repo`):

```
devops-gitops-repo/
├── apps/
│   ├── devops-app/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── configmap.yaml
│   │   ├── overlays/
│   │   │   ├── dev/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── replicas.yaml
│   │   │   ├── staging/
│   │   │   │   └── kustomization.yaml
│   │   │   └── prod/
│   │   │       └── kustomization.yaml
│   │   └── helm-values/
│   │       ├── values-dev.yaml
│   │       ├── values-staging.yaml
│   │       └── values-prod.yaml
├── infrastructure/
│   ├── argocd-config/
│   ├── cert-manager/
│   └── ingress-nginx/
└── README.md
```

Example kustomization.yaml:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

replicas:
- name: devops-app
  count: 2

commonLabels:
  app: devops-app
  managed-by: argocd

commonAnnotations:
  kustomize.config.k8s.io/needs-hash: "true"

resources:
- deployment.yaml
- service.yaml
- configmap.yaml
```

### 6.4 Create ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-app-dev
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourusername/devops-gitops-repo
    targetRevision: main
    path: apps/devops-app/overlays/dev
  
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Auto-sync when cluster drifts
    syncOptions:
    - CreateNamespace=true
  
  # Health assessment
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

Apply and verify:

```bash
# Create the application
kubectl apply -f argocd-application.yaml

# Monitor sync status
argocd app get devops-app-dev
argocd app wait devops-app-dev --health

# Manual sync if needed
argocd app sync devops-app-dev
```

---

## Phase 7: Security & Scanning

### 7.1 Container Image Scanning (Trivy)

```bash
# Install Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy

# Scan Docker image
trivy image devops-app:1.0.0

# Scan with policy
trivy image --severity CRITICAL,HIGH devops-app:1.0.0

# Export results
trivy image --format json --output results.json devops-app:1.0.0
```

### 7.2 Image Signing (cosign)

```bash
# Install cosign
wget https://github.com/sigstore/cosign/releases/download/v2.0.0/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign

# Generate signing key pair
cosign generate-key-pair

# Sign image
cosign sign --key cosign.key devops-app:1.0.0

# Verify signature
cosign verify --key cosign.pub devops-app:1.0.0
```

### 7.3 Kubernetes Policy Enforcement (Kyverno)

Install Kyverno:

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
```

Create a policy:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-image-registry
spec:
  validationFailureAction: enforce
  rules:
  - name: validate-registry
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Images from untrusted registries are not allowed"
      pattern:
        spec:
          containers:
          - image: "registry.example.com/*"
```

Apply:

```bash
kubectl apply -f kyverno-policy.yaml

# Test
kubectl run nginx --image=nginx  # Should be rejected
```

---

## Phase 8: Observability Stack

### 8.1 Install Prometheus + Grafana

Using Helm:

```bash
# Add Prometheus Community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values - <<EOF
prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        cpu: 500m
        memory: 2Gi

grafana:
  adminPassword: admin123
  persistence:
    enabled: true
    size: 10Gi

alertmanager:
  enabled: true
  config:
    global:
      resolve_timeout: 5m
EOF
```

### 8.2 Access Grafana

```bash
# Port forward
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

# Access: http://localhost:3000
# Username: admin
# Password: admin123

# Add Prometheus datasource
# Configuration → Data Sources → Prometheus
# URL: http://prometheus-operated:9090
```

### 8.3 Create Custom Dashboard

```bash
# Port forward Prometheus
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring

# Query Prometheus directly: http://localhost:9090

# Common queries:
# - sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)
# - sum(container_memory_usage_bytes) by (pod)
# - sum(rate(http_requests_total[5m])) by (job)
```

### 8.4 Install Loki for Log Aggregation

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --values - <<EOF
loki:
  auth_enabled: false
  ingester:
    chunk_idle_period: 3m
    max_chunk_age: 1h

promtail:
  enabled: true
EOF
```

---

## Phase 9: Secret Management

### 9.1 Sealed Secrets

```bash
# Install Sealed Secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system

# Install kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/kubeseal-0.24.5-linux-amd64.tar.gz
tar xzf kubeseal-*.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/
```

Seal a secret:

```bash
# Create secret
kubectl create secret generic db-password \
  --dry-run=client \
  --from-literal=password=realprodpass \
  -o yaml > secret.yaml

# Seal it
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Apply sealed secret (safe to commit to Git)
kubectl apply -f sealed-secret.yaml

# Verify unsealing
kubectl get sealedsecret db-password -o yaml
```

### 9.2 SOPS for File Encryption

```bash
# Install SOPS and age
wget https://github.com/getsops/sops/releases/download/v3.10.3/sops-v3.10.3.linux.amd64
chmod +x sops && sudo mv sops /usr/local/bin/

# Install age
wget https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
tar xzf age-v1.2.0-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/ && sudo mv age/age-keygen /usr/local/bin/

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Encrypt file
SOPS_AGE_RECIPIENTS=$(age-keygen -y ~/.config/sops/age/keys.txt) \
  sops --encrypt --age $SOPS_AGE_RECIPIENTS secrets.yaml > secrets.enc.yaml

# Decrypt
sops --decrypt secrets.enc.yaml
```

---

## Phase 10: Advanced Deployments

### 10.1 Canary Deployments with Argo Rollouts

```bash
# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Install Argo Rollouts Kubectl plugin
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts_linux_amd64
chmod +x kubectl-argo-rollouts_linux_amd64
sudo mv kubectl-argo-rollouts_linux_amd64 /usr/local/bin/kubectl-argo-rollouts
```

Create a canary rollout:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: devops-app-canary
  namespace: dev
spec:
  replicas: 5
  selector:
    matchLabels:
      app: devops-app
  template:
    metadata:
      labels:
        app: devops-app
    spec:
      containers:
      - name: app
        image: devops-app:2.0.0
        ports:
        - containerPort: 5000
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: { duration: 5m }
      - setWeight: 40
      - pause: { duration: 5m }
      - setWeight: 60
      - pause: { duration: 5m }
      - setWeight: 100
```

Monitor and promote:

```bash
kubectl argo rollouts get rollout devops-app-canary -n dev --watch
kubectl argo rollouts promote devops-app-canary -n dev
kubectl argo rollouts abort devops-app-canary -n dev
```

### 10.2 Blue-Green Deployments

```yaml
strategy:
  blueGreen:
    activeService: devops-app-active
    previewService: devops-app-preview
    autoPromotionEnabled: false
    maxSurge: 1
```

---

## Phase 11: Chaos Engineering & Resilience

### 11.1 Install Chaos Mesh

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=docker
```

### 11.2 Create Chaos Experiments

Pod failure injection:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure
  namespace: dev
spec:
  action: pod-failure
  mode: one
  duration: "30s"
  scheduler:
    cron: "@every 5m"
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: devops-app
```

Network latency:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay
  namespace: dev
spec:
  action: delay
  mode: all
  delay:
    latency: "100ms"
    jitter: "10ms"
  duration: "2m"
  scheduler:
    cron: "@every 10m"
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: devops-app
```

---

## Complete CI/CD Pipeline

### GitHub Actions Workflow

Create `.github/workflows/ci-cd.yml`:

```yaml
name: DevOps CI/CD Pipeline

on:
  push:
    branches: [main, develop]
    paths:
      - 'src/**'
      - 'Dockerfile'
      - '.github/workflows/**'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/devops-app

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2

    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=sha,prefix={{branch}}-
          type=semver,pattern={{version}}

    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  scan:
    needs: build
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        format: sarif
        output: trivy-results.sarif

    - name: Upload Trivy results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: trivy-results.sarif

  sign:
    needs: [build, scan]
    runs-on: ubuntu-latest
    if: success()

    steps:
    - name: Install cosign
      uses: sigstore/cosign-installer@v3

    - name: Sign container image
      env:
        COSIGN_EXPERIMENTAL: 1
      run: |
        cosign sign --yes \
          ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

  deploy:
    needs: [build, scan, sign]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ secrets.GITOPS_REPO }}
        token: ${{ secrets.GITOPS_PAT }}

    - name: Update image in GitOps repo
      run: |
        yq eval -i '.image.tag = "${{ github.sha }}"' \
          apps/devops-app/overlays/prod/kustomization.yaml

        git config user.name "GitHub Actions"
        git config user.email "actions@github.com"
        git add apps/devops-app/overlays/prod/kustomization.yaml
        git commit -m "Update devops-app image to ${{ github.sha }}"
        git push
```

---

## Troubleshooting & Best Practices

### Common Issues

**k3d cluster not starting:**
```bash
k3d cluster delete devops-cluster
k3d cluster create devops-cluster --servers 1 --agents 2
```

**Pods stuck in pending:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl top nodes  # Check resource availability
```

**Docker image not found in cluster:**
```bash
# Load local Docker image into k3d
k3d image import your-image:tag -c devops-cluster

# Or use image pull policy
kubectl set image deployment/<name> <container>=image:tag --record -n <ns>
```

### Best Practices

1. **Use namespaces** for environment isolation
2. **Set resource limits** to prevent node starvation
3. **Enable RBAC** and use service accounts
4. **Encrypt secrets** at rest and in transit
5. **Use readiness/liveness probes** for reliability
6. **Implement network policies** for security
7. **Monitor everything** with Prometheus/Grafana
8. **Use GitOps** for all deployments
9. **Automate security scanning** in CI/CD
10. **Document and version** all configurations

### Performance Tuning

```bash
# Enable metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Check node metrics
kubectl top nodes
kubectl top pods -A

# View events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Full Cleanup

```bash
# Delete k3d cluster
k3d cluster delete devops-cluster

# Destroy Vagrant VM
vagrant destroy -f

# Clean up Docker
docker system prune -a

# Clean up local files
rm -rf ~/.kube/config.bak
rm -rf terraform.tfstate*
```

---

## Appendix: Helpful Commands

### kubectl

```bash
# Cluster info
kubectl cluster-info
kubectl api-resources
kubectl api-versions

# Deployments
kubectl apply -f manifest.yaml
kubectl get deployments -A
kubectl describe deployment <name> -n <ns>
kubectl logs deployment/<name> -n <ns>
kubectl exec -it pod/<name> -n <ns> -- /bin/bash

# Services
kubectl get svc -A
kubectl port-forward svc/<name> 8080:5000 -n <ns>

# Scaling
kubectl scale deployment/<name> --replicas=5 -n <ns>

# Rollouts
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
```

### Helm

```bash
helm repo add <name> <url>
helm repo update
helm search repo <keyword>
helm install <release> <chart> -n <ns> --create-namespace
helm upgrade <release> <chart> -f values.yaml
helm rollback <release> <revision>
helm uninstall <release> -n <ns>
helm get values <release> -n <ns>
helm lint <chart>
```

### Docker

```bash
docker build -t image:tag .
docker run -d --name container -p 8080:5000 image:tag
docker exec -it container /bin/bash
docker logs -f container
docker ps / docker ps -a
docker network ls / docker volume ls
docker compose up -d
docker compose logs -f
```

---

## Resources & References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Helm Charts](https://artifacthub.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/)
- [Terraform AWS/K8s Providers](https://registry.terraform.io/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Prometheus Metrics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

---

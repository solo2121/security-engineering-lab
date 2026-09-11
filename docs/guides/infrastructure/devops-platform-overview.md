
> **Standalone tutorial, not this repo's lab.** This guide has you build your
> own throwaway VM with Minikube and Jenkins to learn core DevOps concepts.
> It is intentionally independent of `labs/infrastructure/devops-linux-lab/`,
> which uses k3s, Harbor, and Argo CD instead — see that lab's
> [README](../../../labs/infrastructure/devops-linux-lab/README.md) if you
> want to work with the actual repository lab.

---

## Table of Contents

- Lab Overview
    
- 0. Local Lab Setup (Vagrant + KVM)
        
- System Requirements
    
- 1. System Preparation
        
- 2. Docker
        
- 3. kubectl
        
- 4. Minikube
        
- 5. Jenkins
        
- 6. Prometheus
        
- 7. Grafana
        
- 8. Architecture
        
- 9. DevOps Workflow
        
- 10. Hands-On Labs
        
- 11. Troubleshooting
        
- 12. Cleanup
        
- 13. Next Steps: Beyond This Overview
        

---

# Lab Overview

A fully structured end-to-end DevOps lab using:

- CI/CD: Jenkins
    
- Containers: Docker
    
- Orchestration: Minikube (Kubernetes)
    
- Monitoring: Prometheus
    
- Visualization: Grafana
    

Ideal for learning real DevOps workflows, CI/CD pipelines, and building a strong portfolio project.

---

# Compatibility

This lab is designed for:

- Ubuntu 24.04 LTS (primary tested version)
    
- Ubuntu 24.10+
    
- Future Ubuntu LTS releases (including 26.04+)
    
- Debian-based systems with minor adjustments
    

This project avoids hardcoded OS versions to ensure long-term compatibility.

---

# 0. Local Lab Setup (Vagrant + KVM)

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y curl wget git ca-certificates gnupg lsb-release \
  qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst \
  vagrant vagrant-libvirt

sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

sudo systemctl enable --now libvirtd

virsh list --all
```

Log out and back in after adding groups.

---

## Recommended Vagrantfile (Optimized + Port Forwarding)

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2404"

  config.vm.network "private_network", type: "dhcp"

  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.network "forwarded_port", guest: 3000, host: 3000
  config.vm.network "forwarded_port", guest: 9090, host: 9090

  config.vm.provider "libvirt" do |v|
    v.memory = 8192
    v.cpus = 4
    v.nested = true
  end
end
```

---

# System Requirements

- 8 GB RAM minimum (16 GB recommended)
    
- 4 CPU cores minimum
    
- KVM enabled virtualization
    
- 20+ GB free disk space
    
- Ubuntu/Debian host system
    

---

# 1. System Preparation

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ca-certificates gnupg lsb-release
```

---

# 2. Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

## Future-proof repository setup

```bash
echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list
```

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

Test:

```bash
docker run hello-world
```

---

# 3. kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

Test:

```bash
kubectl version --client
```

---

# 4. Minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

Start cluster:

```bash
minikube start --driver=docker
kubectl get nodes
```

---

# 5. Jenkins

```bash
sudo mkdir -p /usr/share/keyrings

wget -O /usr/share/keyrings/jenkins-keyring.asc \
https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian-stable binary/" | \
sudo tee /etc/apt/sources.list.d/jenkins.list
```

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk jenkins

sudo systemctl enable --now jenkins
```

Get password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Access:

```
http://localhost:8080
```

---

# 6. Prometheus

```bash
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
```

Download:

```bash
wget https://github.com/prometheus/prometheus/releases/download/v3.10.0/prometheus-3.10.0.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
cd prometheus-*
```

Install binaries:

```bash
sudo mv prometheus promtool /usr/local/bin/
sudo mv consoles console_libraries /etc/prometheus/
```

Configuration:

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
```

---

## Prometheus systemd service

```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

---

# 7. Grafana

```bash
sudo apt install -y software-properties-common

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://apt.grafana.com/gpg.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install -y grafana

sudo systemctl enable --now grafana-server
```

Access:

```
http://localhost:3000
```

Default login:

- admin / admin
    

---

# 8. Architecture

Original:

```
Jenkins
   ↓
Docker Build
   ↓
Minikube (Kubernetes)
   ↓
Prometheus
   ↓
Grafana
```

Improved:

```
GitHub
  ↓
Jenkins CI
  ↓
Docker Build
  ↓
Kubernetes (Minikube)
  ↓
Prometheus (metrics)
  ↓
Grafana (visualization)
```

---

# 9. DevOps Workflow

1. Code push to Git repository
    
2. Jenkins pipeline triggered
    
3. Build and test application
    
4. Build Docker image
    
5. Push image to registry
    
6. Deploy to Kubernetes
    
7. Monitor with Prometheus
    
8. Visualize with Grafana
    

---

## Extended CI/CD Flow

```
Developer Push
   ↓
GitHub Webhook
   ↓
Jenkins Pipeline
   ↓
Test + Build
   ↓
Docker Image Build
   ↓
Trivy Security Scan
   ↓
Push to Registry
   ↓
Deploy to Kubernetes
   ↓
Prometheus Scraping
   ↓
Grafana Dashboard
```

---

# 10. Hands-On Labs

Core:

- Jenkins pipeline creation
    
- Multi-tier application deployment
    
- Ingress configuration
    

Monitoring:

- Node Exporter setup
    
- Grafana dashboards (ID 1860)
    
- Alerts configuration
    

Advanced:

- Helm deployments
    
- Canary deployments
    
- Security scanning with Trivy
    
- Persistent volumes
    

---

# 11. Troubleshooting

```bash
export PATH=$PATH:/usr/local/bin
```

Minikube:

```bash
minikube delete
minikube start --driver=docker
```

Jenkins:

```bash
sudo systemctl status jenkins
sudo journalctl -u jenkins -f
```

Docker permissions:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

# 12. Cleanup

```bash
minikube delete
docker system prune -a
vagrant destroy -f
```

---

# 13. Next Steps: Beyond This Overview

This overview covers the core lab (Vagrant/KVM → Docker → Minikube → Jenkins →
Prometheus/Grafana). Once that's running, the natural next steps —
Infrastructure as Code, GitOps, container scanning, and progressive delivery —
are covered in full, working depth in
[`complete-devops-platform-guide.md`](complete-devops-platform-guide.md),
including:

- **Terraform** — provisioning the Kubernetes resources this lab creates
  manually (see *Phase 3: Infrastructure as Code*)
- **ArgoCD / GitOps** — full repo structure and Application manifests, not
  just the concept (see *Phase 6: GitOps & Continuous Deployment*)
- **Trivy image scanning** and **Argo Rollouts canary deployments** (see
  *Phase 7* and *Phase 10*)

This overview intentionally stops short of those phases so it stays a quick,
linear read; the complete guide picks up exactly where this one ends.
    
  

---
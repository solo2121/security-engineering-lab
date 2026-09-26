# DevOps / DevSecOps Lab

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-KVM%2Flibvirt%20%7C%20VirtualBox-blue)](https://www.linux-kvm.org/)
[![Version](https://img.shields.io/badge/version-8.2.0-green)](https://github.com/solo2121/security-engineering-lab)
[![Vagrant](https://img.shields.io/badge/Vagrant-%3E%3D2.4-1563FF)](https://www.vagrantup.com/)

**Version 8.2.0 — Enterprise DevSecOps Lab with Integrated CI/CD Platform**

A full enterprise-grade cloud-native lab built with Vagrant and KVM/libvirt. Designed for hands-on learning, certification practice, and portfolio development across Kubernetes, GitOps, IaC, observability, and runtime security.

---

## Recent Additions

- **Integrated CI/CD Platform:** Added a dedicated `cicd-server` VM running Gitea, Jenkins, SonarQube, Vault, and OWASP ZAP for end-to-end DevSecOps pipeline practice.
- **Realistic Attack Scenarios:** Expanded the lab with modern, realistic attack scenarios and intentionally vulnerable deployments to bridge the gap between infrastructure engineering and security.
- **IaC Security Practice:** Added a Terraform state file with exposed secrets to practice secret management and IaC security scanning.
- **AI Security Testing:** Added an indirect prompt injection (RAG) scenario to practice securing AI/LLM pipelines integrated with enterprise infrastructure.
- **Active Directory Threat Coverage:** Added modern enterprise attack scenarios to reflect current real-world Active Directory threats.

---

## What Changed in v8.2.0

- Added an integrated **CI/CD server** (`cicd-server`) running Gitea, Jenkins, SonarQube, HashiCorp Vault, and OWASP ZAP for a complete DevSecOps pipeline.
- Provisioned the CI/CD environment with a sample Jenkins pipeline (`DevSecOps-Pipeline.groovy`) and a sample Flask application, both wired to Harbor, Gitleaks, and Trivy.
- Added Gitleaks and Trivy CLI tools on `cicd-server` for automated secret and container image scanning.
- Added port forwarding for Gitea (3000), Jenkins (8080), Jenkins agent (50000), SonarQube (9000), Vault (8200), and ZAP (8090).
- `cicd-server` is included in the `full` lab profile, or can be started independently with `START_VMS=cicd-server` without affecting the rest of the lab.
- Existing K3s, Harbor, Argo CD, and lab infrastructure are unaffected.

> **Known issue — host port 8080 conflict:** `devops-1` forwards its Ingress
> NGINX HTTP endpoint (guest `80`) to host port `8080`, and Jenkins on
> `cicd-server` also forwards to host port `8080`. Running both VMs together
> (e.g. `LAB_PROFILE=full`) will fail with a Vagrant port-collision error.
> Until this is fixed upstream, avoid starting both at once, or edit the
> `JENKINS_PORT` constant near the top of the Vagrantfile to a free host
> port (e.g. `18080`) before running `vagrant up`.

---

## What Changed in v8.1.0

- Added automated DevSecOps attack scenarios and intentionally vulnerable deployments.
- Added a backdoored image build and Harbor push scenario.
- Added a Terraform state file with intentionally leaked secrets for IaC security practice.
- Added an indirect prompt injection (RAG) scenario for AI/LLM security testing.

---

## What Changed in v8.0.0

- Added **OpenTofu** (open-source Terraform fork) alongside Terraform.
- Added **Kind lab** — Kubernetes in Docker with a fully automated multi-node cluster.
- Added **K3d lab** — K3s in Docker with automatic cluster creation.
- **No hardcoded Harbor password** — interactive prompt or `HARBOR_PASS` env var.
- Dynamic architecture detection for binary downloads (`amd64` / `arm64`).
- `vagrant_manager.py` — interactive TUI for managing all VMs by group, supporting both KVM/libvirt and VirtualBox.
- `validate-lab.sh` — automated health checks for the full lab stack.
- `--wait=false` on CRD deletion to prevent Argo CD finalizer hangs.
- Kyverno retry logic with namespace cleanup between attempts.

---

## Lab Architecture

![DevOps DevSecOps Lab network topology diagram](diagrams/devops-topology.png)

```text
Host (Linux, KVM/libvirt)
│
├── K3s Kubernetes Cluster
│   ├── devops-1 (control plane + Harbor + ArgoCD + monitoring)
│   ├── worker-1 (k3s agent)
│   └── worker-2 (k3s agent)
│
├── Modern Kubernetes Labs
│   ├── kind-lab  (Kind: Kubernetes in Docker, 1 control + 2 workers)
│   └── k3d-lab   (K3d: K3s in Docker, 1 server + 2 agents)
│
├── Linux Practice Nodes
│   ├── ubuntu-lab  (Ubuntu 24.04)
│   ├── rocky-lab   (Rocky Linux 10)
│   ├── alma-lab    (AlmaLinux 10)
│   └── suse-lab    (openSUSE Leap 15.6)
│
├── CI/CD Server
│   └── cicd-server (Gitea + Jenkins + SonarQube + Vault + OWASP ZAP)
│
└── Ansible Management Nodes
    ├── node1 (Ubuntu 24.04)
    └── node2 (Ubuntu 24.04)
```

---

## VM Inventory

| VM | IP | Role | Memory | CPUs |
|---|---|---|---|---|
| devops-1 | auto-detected .114 | K3s control plane + all services | 8192 MB | 4 |
| worker-1 | auto-detected .11 | K3s worker agent | 2048 MB | 2 |
| worker-2 | auto-detected .12 | K3s worker agent | 2048 MB | 2 |
| kind-lab | auto-detected .200 | Kind cluster (Docker) | 4096 MB | 2 |
| k3d-lab | auto-detected .201 | K3d cluster (Docker) | 4096 MB | 2 |
| ubuntu-lab | auto-detected .20 | Linux practice | 1024 MB | 1 |
| rocky-lab | auto-detected .21 | Linux practice | 1024 MB | 1 |
| alma-lab | auto-detected .22 | Linux practice | 1024 MB | 1 |
| suse-lab | auto-detected .23 | Linux practice | 1024 MB | 1 |
| node1 | auto-detected .30 | Ansible managed node | 1024 MB | 1 |
| node2 | auto-detected .31 | Ansible managed node | 1024 MB | 1 |
| cicd-server | auto-detected .50 | Gitea + Jenkins + SonarQube + Vault + ZAP | 4096 MB | 2 |

IPs are auto-detected from your libvirt network at runtime.

---

## Enterprise Stack

| Tool | Version | Purpose |
|---|---|---|
| k3s | v1.31.4+k3s1 | Production Kubernetes distribution |
| Harbor | Chart 1.14.0 | Container registry with Trivy scanning |
| Argo CD | 7.7.5 | GitOps continuous delivery |
| Prometheus + Grafana | 68.3.0 | Metrics and dashboards |
| Loki + Promtail | 3.2.1 | Log aggregation |
| Falco | 2.3.0 | Runtime security |
| Kyverno | 3.3.7 | Policy enforcement |
| Cert-Manager | 1.16.2 | TLS automation |
| Terraform | 1.9.8 | Infrastructure as Code |
| OpenTofu | 1.8.0 | Open-source Terraform fork |
| Kind | v0.24.0 | Kubernetes in Docker |
| K3d | v5.7.5 | K3s in Docker |
| Ingress NGINX | v1.11.3 | Kubernetes ingress controller |
| Gitea | 1.24.3 | Git server / CI trigger source |
| Jenkins | 2.516.2-lts-jdk17 | CI/CD automation server |
| SonarQube | 25.7 | Static analysis (SAST) |
| HashiCorp Vault | 1.18.2 | Secrets management (dev mode) |
| OWASP ZAP | 2.16.1 | Dynamic analysis (DAST) |
| Gitleaks | 8.18.4 | Secret scanning CLI |
| Trivy (CI/CD host) | 0.57.1 | Container image scanning CLI |

---

## Requirements

- Linux host with KVM/QEMU and hardware virtualization enabled.
- Vagrant >= 2.4 with `vagrant-libvirt` plugin.
- 32 GB RAM recommended (16 GB minimum for core cluster only).
- 200 GB free disk space.
- Ruby >= 2.5 (for interactive password prompt).

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils virt-manager vagrant ruby

sudo usermod -aG libvirt $USER
newgrp libvirt

vagrant plugin install vagrant-libvirt
```

---

## VirtualBox Provider

For hosts without KVM/libvirt (macOS, Windows, or Linux hosts where libvirt
isn't available): this lab uses a single unified
[`Vagrantfile`](Vagrantfile) that supports both KVM/libvirt and
VirtualBox — the same VM inventory, `LAB_PROFILE`/`START_VMS` selection
logic, and provisioning scripts, targeting whichever provider you select
with `--provider` (or `VAGRANT_DEFAULT_PROVIDER`).

**Requirements:** VirtualBox 7.0+, Vagrant >= 2.4 (VirtualBox support is
built in, no provider plugin required), Ruby >= 2.5. Not supported on Apple
Silicon/ARM hosts (VirtualBox is Intel/AMD x86_64 only).

```bash
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab/labs/infrastructure/devops-linux-lab
export HARBOR_PASS='YourStrongPassword'   # or answer the interactive prompt
vagrant validate
vagrant up --provider=virtualbox
vagrant status
```

```bash
vagrant provision
vagrant reload
vagrant halt
vagrant destroy -f
```

Deployment profiles (`LAB_PROFILE=minimal|dev|full`) and `START_VMS=` work
the same as documented under [Quick Start](#quick-start). Set
`LAB_GUI=true` to open a VirtualBox GUI console per VM instead of running
headless.

**Known limitation:** nested virtualization for Kind/K3d/K3s is enabled via
`--nested-hw-virt` on the VirtualBox provider block; confirm your host CPU
and VirtualBox version support nested virtualization if those workloads
fail to start.

**Troubleshooting:** VirtualBox-specific issues (missing `VBoxManage`,
`vboxusers` group permissions, internal-network conflicts, Guest Additions
mismatches) are the same as documented in the [AD Pentest Lab's VirtualBox
Provider troubleshooting table](../../security/active-directory/base/README.md#troubleshooting).

---

## Quick Start

### Check host readiness

```bash
# From the repo root — validates virtualization, provider, plugins, disk/RAM
./scripts/check-prerequisites.sh
```

### Set Harbor password before starting

```bash
# Recommended: set before vagrant up
export HARBOR_PASS='YourStrongPassword'
```

If you do not set it, Vagrant will prompt you interactively when provisioning begins.

### Deploy the minimal cluster (control plane + 1 worker)

```bash
cd labs/infrastructure/devops-linux-lab

LAB_PROFILE=minimal vagrant up
```

### Deploy the full lab

```bash
LAB_PROFILE=full vagrant up
```

### Deployment profiles

| Profile | VMs Started |
|---|---|
| `minimal` | devops-1, worker-1 |
| `dev` | devops-1, worker-1, node1, node2 |
| `full` | All 12 VMs |

### Start specific VMs

```bash
START_VMS=kind-lab,k3d-lab vagrant up
```

---

## Lab Manager

Use the included manager script instead of typing raw vagrant commands:

```bash
python3 ./scripts/vagrant_manager.py
```

Targets KVM/libvirt by default on Linux (VirtualBox elsewhere), matching
the Vagrantfile's own default. Override with `--provider virtualbox` or
`--provider libvirt`, or set `VAGRANT_DEFAULT_PROVIDER`.

Groups available from the menu:
- DevOps (requires Harbor password once per session).
- Workers.
- Ansible nodes.
- Linux labs.
- Modern labs (Kind + K3d).

---

## Accessing Services

| Service | URL | Credentials |
|---|---|---|
| Harbor | `https://MASTER_IP:30001` | admin / (your HARBOR_PASS) |
| Argo CD | `https://MASTER_IP:30003` | admin / (see argocd-initial-admin-secret) |
| Grafana | `https://MASTER_IP:<auto-detected-port>` | admin / admin |
| Prometheus | kubectl port-forward | — |
| K3s API | `https://MASTER_IP:16443` | kubeconfig at `/vagrant/kubeconfig.yaml` |
| Gitea | `http://localhost:3000` | Set on first visit |
| Jenkins | `http://localhost:8080` | See "Jenkins Initial Admin Password" below |
| SonarQube | `http://localhost:9000` | admin / admin |
| Vault | `http://localhost:8200` | token: `root` (dev mode) |
| OWASP ZAP | `http://localhost:8090` | — |

`MASTER_IP` is auto-detected at boot and printed to the console.

Argo CD initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Port-forward alternatives:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

---

## Kind Lab

SSH into the Kind VM and use a fully automated multi-node cluster:

```bash
vagrant ssh kind-lab

# Cluster is ready automatically
kubectl get nodes
kubectl cluster-info

# Practice workloads
kubectl apply -f /opt/kind/examples/
```

---

## K3d Lab

```bash
vagrant ssh k3d-lab

# Cluster is ready automatically
kubectl get nodes

# Create additional clusters for practice
k3d cluster create test-cluster --servers 1 --agents 2
k3d cluster list
```

---

## CI/CD Server

The `cicd-server` VM hosts a self-contained DevSecOps pipeline stack: Gitea (source control), Jenkins (automation), SonarQube (SAST), Vault (secrets), and OWASP ZAP (DAST), plus Gitleaks and Trivy CLI tools.

```bash
vagrant ssh cicd-server

# Get the Jenkins initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# Scan the sample app for leaked secrets
gitleaks detect -r /opt/sample-app -v

# Scan a built image for vulnerabilities
trivy image app:latest --severity HIGH,CRITICAL

# Push an image to the lab's Harbor registry
harbor-push my-app 1.0
```

A sample pipeline (`/opt/jenkins/pipelines/DevSecOps-Pipeline.groovy`) and sample Flask app (`/opt/sample-app/`) are provisioned automatically, wired to Gitea checkout, Gitleaks secret scanning, Trivy image scanning, and a Harbor push.

Only start the CI/CD server on its own with:

```bash
START_VMS=cicd-server vagrant up
```

---

## Linux Practice

```bash
vagrant ssh rocky-lab    # RHCSA / RHCE
vagrant ssh alma-lab     # Enterprise Linux
vagrant ssh ubuntu-lab   # LFCS / Ubuntu
vagrant ssh suse-lab     # openSUSE / SLES
```

Practice topics: LVM, SELinux, networking, systemd, users and permissions, package management, cron, firewalls.

---

## Ansible Practice

```bash
vagrant ssh devops-1

# SSH keys are automatically shared to node1 and node2
ansible all -i 'node1,node2,' -m ping
ansible-playbook your-playbook.yml -i inventory/
```

---

## Validate the Lab

Run the automated health check after deployment:

```bash
./scripts/validate-lab.sh
```

Checks: RAM, CPU, disk, installed tools, VM states, Kubernetes cluster health, CIS Kubernetes Benchmark compliance (kube-bench), network connectivity, service availability.

---

## Deployment Workflow

1. Terraform / OpenTofu provisions infrastructure definitions.
2. Vagrant bootstraps VMs with k3s and Docker.
3. Harbor installs with airgap image seeding (40+ images).
4. K3s `registries.yaml` configured to pull from Harbor.
5. Kyverno, Falco, Cert-Manager deploy via Helm.
6. Prometheus + Grafana + Loki observability stack deploys.
7. Argo CD installs with clean CRD removal and NodePort access.
8. Kind and K3d clusters bootstrap automatically.
9. Ansible SSH keys distributed to managed nodes.

---

## FAST_BOOT Mode

Skip Harbor, Helm installs, and enterprise tooling for rapid iteration:

```bash
FAST_BOOT=true vagrant up devops-1
```

---

## Cleanup

```bash
# Stop all VMs (preserves state)
vagrant halt

# Destroy all VMs (clean slate)
vagrant destroy -f
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| VM fails to start | Confirm KVM is enabled in BIOS and user is in `libvirt` group. |
| Workers not joining k3s | Wait for devops-1 to fully initialize; check `/vagrant/.cluster_state.json`. |
| Harbor API never healthy | Increase memory for devops-1; check `kubectl get pods -n harbor`. |
| Kyverno install fails | Script retries 3 times with namespace cleanup; check `kubectl get pods -n kyverno`. |
| Argo CD pods stuck | CRD finalizers sometimes hang; script uses `--wait=false` to prevent this. |
| Kind cluster not created | SSH into kind-lab and run `kind create cluster --config /opt/kind/config.yaml --name lab`. |
| K3d cluster not ready | SSH into k3d-lab and check `k3d cluster list`. |
| Harbor password prompt | Set `export HARBOR_PASS='yourpassword'` before `vagrant up`. |
| Out of memory | Use `LAB_PROFILE=minimal` or `START_VMS=` to deploy only needed VMs. |
| CI/CD service unreachable | SSH into `cicd-server` and check `docker ps`; restart with `docker restart <service>`. |
| Jenkins password unknown | Run `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` from inside `cicd-server`. |
| Port 8080 already in use | `devops-1` (Ingress) and `cicd-server` (Jenkins) both default to host port 8080. Don't start both at once, or change `JENKINS_PORT` in the Vagrantfile. |

---

## Lab Documentation

In-depth docs for this lab live under [`docs/`](docs/):

| Doc | What it covers |
|---|---|
| [`docs/lab-guide.md`](docs/lab-guide.md) | Practical, task-by-task guide to working the lab |
| [`docs/architecture.md`](docs/architecture.md) | Lab architecture and VM/service topology |
| [`docs/k8s-setup.md`](docs/k8s-setup.md) | K3s cluster provisioning details |
| [`docs/devops-workflow.md`](docs/devops-workflow.md) | Terraform → Ansible → Kubernetes → GitOps pipeline |
| [`docs/linux-labs.md`](docs/linux-labs.md) | Linux administration practice exercises |
| [`docs/security-hardening.md`](docs/security-hardening.md) | Kubernetes RBAC and system hardening steps |

---

## Related Labs

- [`../../../labs/security/active-directory/base/`](../../../labs/security/active-directory/base/) — Active Directory pentest lab.
- [`../../../labs/security/active-directory/vlan-segmented/`](../../../labs/security/active-directory/vlan-segmented/) — VLAN edition.
- [`../../../tools/sysadmin/`](../../../tools/sysadmin/) — Linux administration scripts.

---

## License

[MIT License](../../../LICENSE) — Author: Miguel A. Carlo

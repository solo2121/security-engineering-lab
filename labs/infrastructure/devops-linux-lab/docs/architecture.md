# DevOps Lab Architecture

**Version 8.0.0**

---

## System Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                     Linux Host (KVM/libvirt)                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  K3s Kubernetes Cluster                 │   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐    │   │
│  │  │  devops-1   │  │  worker-1    │  │   worker-2    │    │   │
│  │  │ Control     │  │ K3s Agent    │  │ K3s Agent     │    │   │
│  │  │ Plane       │  │              │  │               │    │   │
│  │  │ Harbor      │  │              │  │               │    │   │
│  │  │ Argo CD     │  │              │  │               │    │   │
│  │  │ Prometheus  │  │              │  │               │    │   │
│  │  │ Grafana     │  │              │  │               │    │   │
│  │  │ Falco       │  │              │  │               │    │   │
│  │  │ Kyverno     │  │              │  │               │    │   │
│  │  └─────────────┘  └──────────────┘  └───────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Modern Kubernetes Labs                      │    │
│  │                                                         │    │
│  │  ┌─────────────────────┐  ┌─────────────────────────┐   │    │
│  │  │      kind-lab       │  │        k3d-lab          │   │    │
│  │  │ Kind cluster        │  │ K3d cluster             │   │    │
│  │  │ 1 control + 2 work. │  │ 1 server + 2 agents     │   │    │
│  │  └─────────────────────┘  └─────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Linux Practice Nodes                   │    │
│  │                                                         │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │    │
│  │  │ubuntu-lab│  │rocky-lab │  │alma-lab  │  │suse-lab │  │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Ansible Managed Nodes                   │    │
│  │           ┌──────────┐  ┌──────────┐                    │    │
│  │           │  node1   │  │  node2   │                    │    │
│  │           └──────────┘  └──────────┘                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │       Libvirt Network (auto-detected, dynamic base IP) │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## IP Address Allocation

IPs are auto-detected from the libvirt network at runtime. The base is derived from `virsh net-dumpxml vagrant-libvirt`, with `default` as a fallback and `192.168.121.0/24` as the final fallback.

| VM | Octet | Typical IP |
|---|---|---|
| devops-1 | .114 | 192.168.121.114 |
| worker-1 | .11 | 192.168.121.11 |
| worker-2 | .12 | 192.168.121.12 |
| kind-lab | .200 | 192.168.121.200 |
| k3d-lab | .201 | 192.168.121.201 |
| ubuntu-lab | .20 | 192.168.121.20 |
| rocky-lab | .21 | 192.168.121.21 |
| alma-lab | .22 | 192.168.121.22 |
| suse-lab | .23 | 192.168.121.23 |
| node1 | .30 | 192.168.121.30 |
| node2 | .31 | 192.168.121.31 |

Actual IPs depend on your libvirt configuration. Check `MASTER_IP` in the Vagrant startup output for the real address.

---

## Service Port Map

| Service | Protocol | Port | Access |
|---|---|---|---|
| Harbor registry | HTTPS | 30001 | NodePort |
| Argo CD HTTP | HTTP | 30003 | NodePort |
| Argo CD HTTPS | HTTPS | 30004 | NodePort |
| K3s API | HTTPS | 16443 | Port forward |
| Grafana | HTTP | auto | NodePort (auto-assigned) |
| Prometheus | HTTP | 9090 | Port forward |
| Ingress HTTP | HTTP | 8080 | Host port forward |
| Ingress HTTPS | HTTPS | 8443 | Host port forward |

---

## Image Flow

```text
External Registries        Harbor                     K3s Nodes
(docker.io, quay.io,   →   (devops-1:30001)      →   (devops-1,
 ghcr.io, registry.k8s.io)  airgap project             worker-1, worker-2)

40+ images are seeded     registries.yaml             All image pulls
during provisioning       redirects pulls to Harbor   go through Harbor
```

---

## Kubernetes Architecture

### K3s Cluster

```text
devops-1 (Server)
│
├── kube-apiserver
├── kube-scheduler
├── kube-controller-manager
├── etcd (embedded via k3s)
├── CoreDNS
├── Flannel (VXLAN backend)
├── Local Path Provisioner
│
└── Namespaces
    ├── harbor          → Container registry
    ├── argocd          → GitOps platform
    ├── monitoring      → Prometheus, Grafana, Alertmanager
    ├── falco           → Runtime security
    ├── kyverno         → Policy enforcement
    ├── cert-manager    → TLS certificates
    └── ingress-nginx   → Ingress controller
```

### Kind Lab Cluster

```text
kind-lab VM (Docker host)
│
└── Kind cluster: lab
    ├── control-plane (Docker container)
    ├── worker (Docker container)
    └── worker (Docker container)
```

### K3d Lab Cluster

```text
k3d-lab VM (Docker host)
│
└── K3d cluster
    ├── k3s-server (Docker container)
    ├── k3s-agent (Docker container)
    └── k3s-agent (Docker container)
```

---

## Deployment Sequence

```text
1. Vagrant reads the libvirt network and sets MASTER_IP.
2. Harbor password is read from ENV['HARBOR_PASS'] or prompted interactively.
3. devops-1 provisions:
   a. Base packages.
   b. Docker install (version-pinned, with fallback).
   c. K3s server install (3 retries).
   d. Harbor install and airgap image seeding.
   e. registries.yaml written via Python to avoid shell expansion issues.
   f. K3s restarted with Harbor registry config.
   g. Kyverno (3 retries with cleanup), Falco, and Cert-Manager.
   h. Prometheus, Grafana, and Loki.
   i. Argo CD (full CRD cleanup before install).
   j. Terraform and OpenTofu.
   k. Day-2 tools: k9s, kubectx, kubens, stern.
4. worker-1 and worker-2 wait for .cluster_state.json, then join K3s.
5. kind-lab: Docker install → Kind install → cluster creation.
6. k3d-lab: Docker install → K3d install → cluster creation.
7. Linux labs: base packages plus extra lab disks.
8. Ansible nodes: base packages plus SSH key distribution.
```

---

## Security Architecture

| Layer | Control |
|---|---|
| Registry | Harbor with Trivy vulnerability scanning |
| Runtime | Falco for syscall-level threat detection |
| Policy | Kyverno for admission control and policy enforcement |
| TLS | Cert-Manager for automated certificate management |
| Images | Airgap seeding so all image pulls go through Harbor |
| Passwords | No hardcoded credentials; use ENV or interactive prompt |

---

## Related Documentation

- [`README.md`](../README.md) — Quick start and access guide.
- [`lab-guide.md`](lab-guide.md#1-lab-setup-and-first-boot) — Detailed setup instructions.
- [`security-hardening.md`](security-hardening.md) — Security configuration guide.
- [`k8s-setup.md`](k8s-setup.md) — Kubernetes configuration details.

<div align="center">

# Security Engineering Lab

**Reproducible, isolated labs for Active Directory attack paths, network segmentation, LLM application security, Kubernetes/DevSecOps and Windows hardening.**

Built with Vagrant, Ansible, Bash and Python. Checked by CI on every push.

[![CI](https://github.com/solo2121/security-engineering-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/solo2121/security-engineering-lab/actions/workflows/ci.yml)
[![CodeQL](https://github.com/solo2121/security-engineering-lab/actions/workflows/codeql.yml/badge.svg)](https://github.com/solo2121/security-engineering-lab/actions/workflows/codeql.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![Primary Provider](https://img.shields.io/badge/primary%20provider-KVM%2FQEMU%20%2B%20libvirt-8A2BE2)
![Alternative Provider](https://img.shields.io/badge/alternative%20provider-VirtualBox-183A61)
![Scope](https://img.shields.io/badge/scope-authorized%20%7C%20isolated%20research-red)

[Choose a lab](#choose-your-starting-point) · [Quick start](#quick-start) · [Resources](#resource-planning-and-profiles) · [Learning path](./docs/project/learning-path.md) · [Architecture](./docs/architecture/architecture.md) · [Documentation](./docs/README.md)

<img src="./assets/demos/dc01-02-ad-promotion-success.gif" alt="Active Directory promotion completing successfully on dc01, followed by a reboot" width="760">

<sub>A domain controller promoting itself and rebooting, recorded from <code>vagrant up</code> on the Active Directory lab.</sub>

</div>

> [!CAUTION]
> This repository contains intentionally vulnerable configurations and authorized security-test scenarios. Deploy only on an isolated host and virtual network with no route to production, personal or public networks. Read the [Security Scope](./docs/security-scope.md) and the [Emergency Isolation Runbook](./docs/architecture/emergency-isolation-runbook.md) first.

> [!IMPORTANT]
> **Supported hosts:** Linux with KVM/QEMU and libvirt is the primary provider. VirtualBox is maintained for Intel/AMD x86_64 hosts on Linux, macOS or Windows. **Apple Silicon (ARM64) is not supported.** See [Apple Silicon status](#apple-silicon-status).

**Maintained by** Miguel A. Carlo ([@solo2121](https://github.com/solo2121)) · **Status:** active development · [Roadmap](./docs/project/roadmap.md) · [CHANGELOG](./CHANGELOG.md)

---

## Choose your starting point

| If you want to... | Start here | Guest VMs |
|---|---|---|
| Learn core Active Directory attack paths and how to validate defenses | [Active Directory Security Lab](./labs/security/active-directory/base/) | 6 by default, up to 11 |
| Practise lateral movement across VLANs, routing controls and trust boundaries | [Segmented Active Directory Lab](./labs/security/active-directory/vlan-segmented/) | 3 to 7 by default, up to 12 |
| Attack and defend an LLM application (OWASP Top 10 for LLM Applications, 2026) | [LLM lab](./labs/security/active-directory/base/llm-lab/README.md), part of the AD lab | 1 extra VM (`llm01`) |
| Build Kubernetes, GitOps, observability and runtime-security skills | [DevOps/DevSecOps Platform Lab](./labs/infrastructure/devops-linux-lab/) | 2 by default, up to 12 |
| Study Windows hardening controls mapped to the attacks above | [Windows Server Hardening Lab](./labs/security/windows-hardening/) (experimental) | 1 or 2 |

New to the project? Work through the labs in the order given in the [Learning path](./docs/project/learning-path.md).

### What each lab covers

- **Active Directory Security Lab.** Domain services, Kerberos, LDAP, AD Certificate Services, credential access, privilege escalation, post-compromise analysis and detection concepts. Includes optional targets for cloud, web and legacy-CVE practice.
- **LLM lab** (on the `llm01` VM). Ten OWASP LLM risks, each with an attack, a defense and a verification step; a two-tenant RAG pipeline; an agent that works on the lab's own Active Directory; an optional local model through Ollama. The VM installs Docker, builds the image and starts it on every boot, so it is ready as soon as provisioning ends.

  ```bash
  LAB_PROFILE=llm vagrant up llm01
  ```

- **Segmented Active Directory Lab.** The same domain behind an OPNsense firewall with five VLANs: what changes for an attacker, and for a defender, when the network is no longer flat.
- **DevOps/DevSecOps Platform Lab.** A K3s cluster with Harbor, Argo CD, Prometheus, Grafana, Loki, Falco and Kyverno, plus Kind and K3d clusters, a CI/CD server and Linux practice nodes (Ubuntu, Rocky, Alma, openSUSE).
- **Windows Server Hardening Lab.** A CIS-inspired baseline where each control is documented against the attack technique it stops. Experimental (`v0.1.0`); do the AD lab first.

---

## Quick start

```bash
# From the repository root
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab
./scripts/check-prerequisites.sh --all      # host, provider, plugins, RAM and disk

# From the lab you chose
cd labs/security/active-directory/base
vagrant up --provider=libvirt               # or --provider=virtualbox on an Intel/AMD x86_64 host
vagrant status
```

The Active Directory, Segmented Active Directory and DevOps labs each ship an interactive manager, `python3 scripts/vagrant_manager.py`. The Hardening lab uses plain `vagrant`. Everyday commands are in [Common workflows](./docs/guides/workflows/common-workflows.md).

> [!TIP]
> A finished `vagrant up` only means the machines were created. Before an exercise, run the health checks in the lab README: domain controller readiness for the AD labs, VLAN routing for the segmented lab, node and API readiness for Kubernetes, baseline controls for hardening.

More detail: [Installation Guide](./docs/setup/installation.md) · [Quickstart Examples](./docs/setup/quickstart-examples.md) · [Troubleshooting](./docs/setup/troubleshooting.md)

---

## Resource planning and profiles

Every lab starts a **profile**, a subset of its VMs sized for your host. Pick one with `LAB_PROFILE=<name> vagrant up`. *Guest RAM* is the sum of the VM allocations; *suggested host RAM* adds room for the host OS, the provider and caches.

| Lab | Profile | Guest VMs | Guest RAM | Suggested host RAM | Free disk |
|---|---|---:|---:|---:|---:|
| [Active Directory](./labs/security/active-directory/base/) | `minimal` | 3 | ~10 GB | 16 GB | 200 GB+ |
| | `ad` (default) | 6 | ~19 GB | 24 GB+ | 200 GB+ |
| | `full` | 11 | ~29.5 GB | 40 GB+ | 200 GB+ |
| [Segmented AD](./labs/security/active-directory/vlan-segmented/) | `minimal` | 3 | 10 GB | 16 GB | 80 GB+ |
| | `ad` | 7 | 21 GB | 32 GB+ | 80 GB+ |
| | `full` | 12 | 35.5 GB | 48 GB+ | 80 GB+ |
| [DevOps/DevSecOps](./labs/infrastructure/devops-linux-lab/) | `minimal` (default) | 2 | 10 GB | 16 GB | 200 GB+ |
| | `full` | 12 | ~34 GB | 48 GB+ | 200 GB+ |
| [Windows Hardening](./labs/security/windows-hardening/) | default | 1 | 4 GB | 8 GB | 60 GB+ |
| | `full` | 2 | 6 to 8 GB | 16 GB | 100 GB+ |

> [!NOTE]
> The segmented lab picks a profile from host RAM when `LAB_PROFILE` is unset: `minimal` below 20 GB, `ad` from 20 GB, `full` from 40 GB. Those are switch points, not minimums; a 32 GB host can run `ad`, and a 24 GB host will not fit it comfortably. The AD lab also has `web`, `cloud` and `llm` profiles, and the segmented lab has `cloud` and `llm`. Disk figures are the labs' own guidance; see each lab README for the per-profile detail.

On a small machine, see [Minimal Resource Deployment](./docs/guides/optimization/minimal-resource-deployment.md).

---

## Provider compatibility

| Lab | Linux x86_64 + libvirt | Intel/AMD x86_64 + VirtualBox | Apple Silicon (ARM64) |
|---|:---:|:---:|:---:|
| Active Directory Security Lab | Supported | Supported | Not supported |
| Segmented Active Directory Lab | Supported | Supported | Not supported |
| DevOps/DevSecOps Platform Lab | Supported | Supported | Not supported |
| Windows Server Hardening Lab (experimental) | Supported | Supported | Not supported |

"Supported" means the workflow is maintained and was validated on a reference host. It does not promise identical behavior on every kernel, provider release, plugin version or third-party box revision. Host requirements and Vagrant plugins are in [Platform support](./docs/setup/platform-support.md).

### Apple Silicon status

The labs depend on x86_64 Windows guests and x86_64 Vagrant boxes that have not been validated on ARM64, so Apple Silicon has no supported deployment path. A **DevSecOps Lite (ARM64)** profile is planned but cannot be deployed yet.

---

## See it in action

**DevOps/DevSecOps lab**: K3s ready, air-gapped image seeding into Harbor, security-test scenarios.

| 1. K3s readiness | 2. Harbor image seeding | 3. Security-test scenarios |
|---|---|---|
| ![K3s node Ready and kubectl API ready, with Ingress NGINX installing via Helm](./assets/demos/devops1-01-k3s-ready-ingress.gif) | ![Container images being pulled, tagged and pushed into the air-gapped Harbor registry](./assets/demos/devops1-02-harbor-seeding.gif) | ![Authorized DevSecOps security-test scenarios deploying, ending with Harbor login succeeding](./assets/demos/devops1-03-attack-vectors.gif) |

<details>
<summary><b>Active Directory lab</b>: provider detection, AD promotion, health validation</summary>

| 1. Provider detection | 2. AD promotion | 3. Health validation |
|---|---|---|
| ![vagrant_manager.py detecting the libvirt provider and listing available lab VMs](./assets/demos/dc01-01-boot-provider-detect.gif) | ![Active Directory promotion completing successfully on dc01, followed by a reboot](./assets/demos/dc01-02-ad-promotion-success.gif) | ![Post-boot health check passing and the interactive lab manager menu](./assets/demos/dc01-03-healthcheck-manager.gif) |

</details>

<details>
<summary><b>Segmented Active Directory lab</b>: OPNsense startup, reload, VLAN topology</summary>

| 1. OPNsense startup | 2. Configuration reload | 3. Full topology |
|---|---|---|
| ![Pentest VLAN Lab Manager bringing the OPNsense VM up under the libvirt provider](./assets/demos/opnsense-01-lab-manager-start.gif) | ![OPNsense reloading after configuration and coming back with Machine booted and ready](./assets/demos/opnsense-02-reload-success.gif) | ![OPNsense console showing the complete WAN, LAN and VLAN interface assignments](./assets/demos/opnsense-03-vlan-topology.gif) |

</details>

Full, unedited recordings: [Active Directory lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/dc01.webm) · [DevOps lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/devops1.webm) · [Segmented AD lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/opnsense-vlan.webm). They are release assets, so cloning stays small.

---

## How it is built

[![Enterprise Infrastructure Architecture](./assets/diagrams/architecture-overview.png)](./assets/diagrams/)

Each lab deploys on its own through a provider-aware Vagrant configuration. Deployment logic sits next to the thing it provisions:

- **Active Directory labs:** Vagrant code in `vagrant/` (one file per VM) and shell or PowerShell scripts in `provision/`.
- **DevOps/DevSecOps lab:** Vagrant, shell provisioners, Ansible and Terraform/OpenTofu.
- **Windows Hardening lab:** provisioning is still inside its `Vagrantfile`.

See [Provisioning Philosophy](./docs/architecture/architecture.md#provisioning-philosophy), the [Architecture Overview](./docs/architecture/architecture.md), the [Threat Model](./docs/architecture/threat-model.md) and the [Security Scope](./docs/security-scope.md).

### Quality checks

| Check | What it covers | Runs |
|---|---|---|
| CI | black, ruff and mypy, pytest with an 80% coverage floor, Bats, ShellCheck, secret scanning, `vagrant validate`, documentation and reference checks | every push |
| CodeQL | static analysis of the Python code | every push |
| LLM lab container | image build, boot, smoke test and secure-default checks | every push |
| Full VM deployment | `vagrant up` of a lab on a real host | locally by the maintainer, not in CI |

A green build therefore does not prove that a given `vagrant up` works on your host; each lab README lists its requirements and known limits.

---

## What this project demonstrates

| Area | Evidence | Where |
|---|---|---|
| Active Directory security | Domain deployment, AD CS, attack-path simulation, detection concepts | `labs/security/active-directory/base/` |
| LLM application security | OWASP Top 10 for LLM Applications (2026): vulnerable and defended pair for each risk, challenges, RAG, agent | `labs/security/active-directory/base/llm-lab/` |
| Network segmentation | Firewalled VLANs, routing separation, trust boundaries | `labs/security/active-directory/vlan-segmented/` |
| DevOps/DevSecOps | Kubernetes, GitOps, observability, runtime security, policy | `labs/infrastructure/devops-linux-lab/` |
| Defensive hardening | CIS-inspired controls mapped to attack techniques | `labs/security/windows-hardening/` |
| Infrastructure as Code | Vagrant, Ansible, Bash and Python automation | repository-wide |
| Quality engineering | Tests, linting, documentation checks, CI | `.github/`, `tests/`, `scripts/` |

---

## Documentation

| Start with | Purpose |
|---|---|
| [Documentation Index](./docs/README.md) | Every document, grouped by topic |
| [Learning Path](./docs/project/learning-path.md) | Recommended order through the labs |
| [Installation Guide](./docs/setup/installation.md) | Host and provider setup |
| [Common workflows](./docs/guides/workflows/common-workflows.md) | Everyday Vagrant commands, snapshots and the lab manager |
| [Lab Reset and Cleanup](./docs/guides/workflows/lab-reset-and-cleanup.md) | Snapshot revert, rebuild, full teardown |
| [Architecture](./docs/architecture/architecture.md) · [Threat Model](./docs/architecture/threat-model.md) | Design and trust boundaries |
| [Known limitations](./docs/known-limitations.md) | Platform, lab and validation limits |
| [Portfolio](./docs/project/portfolio.md) · [Roadmap](./docs/project/roadmap.md) | Skills demonstrated and planned work |

---

## Development and contributing

```bash
python3 -m pip install -r requirements-dev.txt
pre-commit install
make lint test validate security docs-refs   # `make help` lists every target
```

Open an issue before a major change, keep pull requests focused, update the docs, add tests for behavior changes, run the checks above, and never commit credentials, keys or host details. For ARM64 work, include compatibility evidence and a clear statement of what is unsupported. Full workflow: [Development](./docs/development.md) · [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## Security and ethics

Use this project only for education, authorized research and defensive practice, on isolated lab networks and on systems you own or have explicit permission to test. Unauthorized access, scanning, exploitation, credential attacks or lateral movement against external systems is prohibited.

[Security Scope](./docs/security-scope.md) · [Threat Model](./docs/architecture/threat-model.md) · [SECURITY.md](SECURITY.md)

---

## Known limitations

- Full-profile deployments need 32 GB or more of host RAM and about 200 GB of free disk, depending on the lab and provider.
- Libvirt needs a Linux host; VirtualBox targets Intel/AMD x86_64. Apple Silicon has no supported path.
- Windows labs use Microsoft evaluation media; you are responsible for the Microsoft license terms.
- The Windows Server Hardening Lab is an experimental `v0.1.0` MVP.
- The LLM lab's injection filter is heuristic and its offline mock model is deliberately gullible, so results with a real model differ. Ollama support is tested against a stub server only.
- CI boots the LLM lab container but does not boot any VM or deploy every environment on every push.
- Third-party Vagrant boxes can change independently of this repository.

The complete list is in [Known limitations](./docs/known-limitations.md).

---

## License

Released under the [MIT License](./LICENSE). Copyright © 2023–2026 Miguel A. Carlo.

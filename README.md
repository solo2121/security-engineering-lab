# Security Engineering Lab

[![CI](https://github.com/solo2121/security-engineering-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/solo2121/security-engineering-lab/actions/workflows/ci.yml)
[![CodeQL](https://github.com/solo2121/security-engineering-lab/actions/workflows/codeql.yml/badge.svg)](https://github.com/solo2121/security-engineering-lab/actions/workflows/codeql.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![Primary Provider](https://img.shields.io/badge/primary%20provider-KVM%2FQEMU%20%2B%20libvirt-8A2BE2)
![Alternative Provider](https://img.shields.io/badge/alternative%20provider-VirtualBox-183A61)
![Scope](https://img.shields.io/badge/scope-authorized%20%7C%20isolated%20research-red)

> A modular, Vagrant-provisioned security engineering laboratory for building, validating, and documenting enterprise security infrastructure in isolated environments.

**Security Engineering Lab** provides reproducible environments for Active Directory security research, network segmentation, Kubernetes and DevSecOps workflows, Windows hardening validation, and infrastructure automation.

Each lab includes deployable infrastructure, provisioning automation, health validation, CI-backed quality checks, and technical documentation.

**Start here:** [Choose a Lab](#choose-your-starting-point) · [Quick Start](#quick-start) · [Learning Path](./docs/project/learning-path.md) · [Architecture](./docs/architecture/architecture.md) · [Portfolio](./docs/project/portfolio.md)

**Maintained by:** Miguel A. Carlo ([@solo2121](https://github.com/solo2121))  
**Status:** Active development — see the [Roadmap](./docs/project/roadmap.md), [CHANGELOG](./CHANGELOG.md), and [CI workflow](https://github.com/solo2121/security-engineering-lab/actions/workflows/ci.yml)

> [!CAUTION]
> This repository contains intentionally vulnerable configurations and authorized security-test scenarios. Deploy only on an isolated host and virtual network with no route to production, personal, or public networks.
>
> Review the [Security Scope](./docs/security-scope.md) and [Emergency Isolation Runbook](./docs/architecture/emergency-isolation-runbook.md) before deployment.

> [!IMPORTANT]
> **Supported hosts:** KVM/QEMU with libvirt is the primary provider on Linux for the full lab portfolio. VirtualBox workflows are maintained for compatible Intel/AMD x86_64 hosts running Linux, macOS, or Windows.
>
> **Apple Silicon (ARM64) is not currently supported or validated.** See [Apple Silicon status](#apple-silicon-status).

---


## Choose your starting point

| If your goal is to... | Start here |
|---|---|
| Learn core Active Directory attack paths and defensive validation | [Active Directory Security Lab](./labs/security/active-directory/base/) |
| Practice segmentation-aware lateral movement, routing controls, and trust boundaries | [Segmented Active Directory Lab](./labs/security/active-directory/vlan-segmented/) |
| Build Kubernetes, GitOps, observability, policy, and runtime-security skills | [DevOps/DevSecOps Platform Lab](./labs/infrastructure/devops-linux-lab/) |
| Study defensive Windows controls mapped to Active Directory attack techniques | [Windows Server Hardening Lab](./labs/security/windows-hardening/) |
| Use an Apple Silicon host | No currently supported deployment path; see [Apple Silicon status](#apple-silicon-status) |

### Resource planning and profiles

| Lab | Default VMs | Host RAM (minimum / recommended) | Free disk | Best for |
|---|---:|---:|---:|---|
| [Active Directory Security Lab](./labs/security/active-directory/base/) | 6; up to 11 with `LAB_PROFILE=full` | 16 GB / 32 GB+ | 200 GB+ | Core AD attack paths and defensive validation |
| [Segmented Active Directory Lab](./labs/security/active-directory/vlan-segmented/) | 3 to 7, chosen from host RAM; up to 12 with `LAB_PROFILE=full` | 16 GB / 32 GB+ | 80 GB+ | Segmentation, routing, and lateral-movement controls |
| [DevOps/DevSecOps Platform Lab](./labs/infrastructure/devops-linux-lab/) | 2; up to 12 with `LAB_PROFILE=full` | 16 GB / 32 GB+ | 200 GB+ | Kubernetes, GitOps, observability, and runtime security |
| [Windows Server Hardening Lab](./labs/security/windows-hardening/) | 1; 2 with `LAB_PROFILE=full` | 8 GB / 16 GB+ | 60 GB+ | Defensive hardening mapped to AD attack techniques |

> [!NOTE]
> Resource figures represent practical **host capacity**, not only aggregate guest allocations. Reserve additional CPU, RAM, and disk capacity for the host OS, provider overhead, Vagrant boxes, snapshots, package caches, and container-image storage.
>
> The Active Directory Security Lab includes an optional `llm` profile that deploys the OWASP Top 10 for LLM Applications training lab.
>
> When `LAB_PROFILE` is not set, the Segmented Active Directory Lab picks a profile from host RAM: `minimal` (3 VMs) below 20 GB, `ad` (7 VMs) from 20 GB, and `full` (12 VMs) from 40 GB. The RAM and disk figures above reflect the `ad` profile; set `LAB_PROFILE=ad` explicitly on a smaller host that meets that profile's minimum. The `full` profile requires approximately 32 GB minimum and 48 GB+ recommended host RAM.
>
> The DevOps/DevSecOps Platform Lab defaults to `LAB_PROFILE=minimal` unless overridden. Review the selected lab README for complete profile-by-profile requirements.
>
> A planned **DevSecOps Lite — ARM64** profile is not currently deployable.

Run the full prerequisite check before deploying:

```bash
./scripts/check-prerequisites.sh --all
```

> [!IMPORTANT]
> Use `./scripts/check-prerequisites.sh --all` before Windows-based, multi-lab, or full-profile workflows.
>
> `make prereq` performs only the baseline prerequisite check. It intentionally does not pass `--all` and may not validate lab-specific dependencies such as Windows guest workflow plugins.

For constrained systems, see [Minimal Resource Deployment](./docs/guides/optimization/minimal-resource-deployment.md).

For the recommended progression from Active Directory fundamentals through segmentation and DevSecOps workflows, see the [Learning Path](./docs/project/learning-path.md).

---
## At a glance

| Item | Details |
|---|---|
| Primary provider | KVM/QEMU with libvirt on Linux |
| Alternative provider | VirtualBox on compatible Intel/AMD x86_64 hosts |
| Lab environments | Active Directory, network-segmented Active Directory, DevOps/DevSecOps, and Windows Server hardening |
| Automation | Vagrant, Ansible, Bash, and Python |
| Cloud-native stack | Selected DevOps/DevSecOps profiles use K3s, Harbor, Argo CD, Prometheus, Grafana, Loki, Falco, and Kyverno |
| Validation | GitHub Actions, pytest, Bats, ShellCheck, and documentation checks |
| Intended use | Authorized research, defensive security practice, and isolated security education |

---
## Quick start

Clone the repository, validate your host, and start the Active Directory Security Lab with the primary Linux provider:

```bash
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab
./scripts/check-prerequisites.sh --all

cd labs/security/active-directory/base
vagrant up --provider=libvirt        # use --provider=virtualbox only on a compatible Intel/AMD x86_64 host
vagrant status
```

The Active Directory, Segmented Active Directory, and DevOps/DevSecOps labs each include an interactive `python3 scripts/vagrant_manager.py` for VM management (the Windows Server Hardening Lab uses plain `vagrant`). See [Common workflows](./docs/guides/workflows/common-workflows.md) for the day-to-day commands.

After deployment, follow the selected lab README and health-validation guidance before beginning an exercise. A successful `vagrant up` does not necessarily mean every guest service, domain role, or Kubernetes component is fully ready.

See the [Installation Guide](./docs/setup/installation.md), [Quickstart Examples](./docs/setup/quickstart-examples.md), and [Learning Path](./docs/project/learning-path.md) for provider setup, deployment patterns, and lab progression.

---

## See it in action

### Active Directory base lab

A complete Active Directory base lab deployment, from provider detection through domain promotion and post-boot health validation.

| 1. Provider detection | 2. AD promotion | 3. Health validation |
|---|---|---|
| ![vagrant_manager.py detecting the libvirt provider and listing available lab VMs](./assets/demos/dc01-01-boot-provider-detect.gif) | ![Active Directory promotion completing successfully on dc01, followed by a reboot](./assets/demos/dc01-02-ad-promotion-success.gif) | ![Post-boot health check passing and the interactive lab manager menu](./assets/demos/dc01-03-healthcheck-manager.gif) |

### DevOps/DevSecOps lab

A complete Linux DevSecOps deployment, from K3s bootstrap through Harbor image seeding and authorized security-test scenario deployment.

| 1. K3s readiness | 2. Air-gapped image seeding | 3. Security-test scenarios |
|---|---|---|
| ![K3s node Ready and kubectl API ready, with Ingress NGINX installing via Helm](./assets/demos/devops1-01-k3s-ready-ingress.gif) | ![Container images being pulled, tagged, and pushed into the air-gapped Harbor registry](./assets/demos/devops1-02-harbor-seeding.gif) | ![Authorized DevSecOps security-test scenarios deploying successfully, ending with Harbor login succeeding](./assets/demos/devops1-03-attack-vectors.gif) |

### Segmented Active Directory lab (OPNsense deployment)

A complete OPNsense deployment for the Segmented Active Directory Lab, from initial boot through reload and interface assignment.

| 1. OPNsense startup | 2. Configuration reload | 3. Full topology |
|---|---|---|
| ![Pentest VLAN Lab Manager bringing the OPNsense VM up under the libvirt provider](./assets/demos/opnsense-01-lab-manager-start.gif) | ![OPNsense reloading after configuration and coming back with Machine booted and ready](./assets/demos/opnsense-02-reload-success.gif) | ![OPNsense console showing the complete WAN, LAN, and VLAN interface assignments](./assets/demos/opnsense-03-vlan-topology.gif) |

Full, unedited deployment recordings are available for the [Active Directory lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/dc01.webm), [DevOps lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/devops1.webm), and [segmented Active Directory lab](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/opnsense-vlan.webm). They are hosted as GitHub Release assets, so cloning the repository stays small.

---

## Lab environments

| Lab | Purpose | Location |
|---|---|---|
| Active Directory Security Lab | Windows enterprise infrastructure, Active Directory security research, identity attack-path simulation, and detection concepts | [labs/security/active-directory/base/](./labs/security/active-directory/base/) |
| Segmented Active Directory Lab | Segmentation-aware Active Directory research, routing controls, trust boundaries, and lateral-movement constraints | [labs/security/active-directory/vlan-segmented/](./labs/security/active-directory/vlan-segmented/) |
| DevOps/DevSecOps Platform Lab | Linux administration, Kubernetes, GitOps, observability, runtime security, and policy enforcement | [labs/infrastructure/devops-linux-lab/](./labs/infrastructure/devops-linux-lab/) |
| Windows Server Hardening Lab | CIS-benchmark-inspired defensive hardening controls mapped to specific AD attack techniques | [labs/security/windows-hardening/](./labs/security/windows-hardening/) |

### Active Directory Security Lab

The Active Directory Security Lab provides Windows enterprise-style infrastructure for authorized identity security research and defensive validation.

It covers Active Directory Domain Services, Kerberos, LDAP, Active Directory Certificate Services, credential-access simulation, privilege-escalation research, post-compromise analysis workflows, and detection-engineering concepts.

It also hosts the OWASP Top 10 for LLM Applications training lab on a dedicated `llm01` VM:

```bash
LAB_PROFILE=llm vagrant up llm01
```

The VM installs Docker, builds the lab image and starts it on every boot, so the lab is ready as soon as provisioning ends. Beyond the per-risk scenarios it includes a two-tenant RAG pipeline, an Active Directory helpdesk agent, ten challenges with attack, defend and verify steps, and an optional real local model through Ollama.

See [`llm-lab/README.md`](./labs/security/active-directory/base/llm-lab/README.md) for the safety model and category-to-endpoint reference.

See the [lab README](./labs/security/active-directory/base/) for provider-specific instructions, resource profiles, validation procedures, and authorized security-testing guidance.

### Segmented Active Directory Lab

The Segmented Active Directory Lab extends the Active Directory Security Lab with controlled routing, separated trust boundaries, and segmentation-aware security testing.

It supports research into lateral-movement constraints, network-security concepts, detection and response across boundaries, and controlled routing between lab segments.

See the [lab README](./labs/security/active-directory/vlan-segmented/) and [segmented lab troubleshooting guide](./labs/security/active-directory/vlan-segmented/docs/troubleshooting.md) for deployment and troubleshooting information.

### DevOps/DevSecOps Platform Lab

The DevOps/DevSecOps Platform Lab focuses on Linux platform engineering, Kubernetes operations, GitOps, observability, runtime security, policy enforcement, container-security testing, and integrated CI/CD validation.

See the [lab README](./labs/infrastructure/devops-linux-lab/) for provider-specific deployment requirements, resource profiles, and validation guidance.

### Windows Server Hardening Lab

The Windows Server Hardening Lab is a defensive counterpart to the Active Directory Security Lab. It uses the same base-box and AD-promotion pattern but applies a hardening baseline instead of intentional misconfigurations.

Each control is documented against the specific attack technique it mitigates, using the AD base lab attack guide as the reference point.

> [!WARNING]
> This lab is experimental (`v0.1.0` MVP) and has not received the same level of real-world testing as the other labs. Complete the Active Directory Security Lab first, then use this environment to study and validate the defensive side.

See the [lab README](./labs/security/windows-hardening/) and [hardening guide](./labs/security/windows-hardening/docs/hardening-guide.md) for the full control list, known limitations, and baseline-validation procedures.

---

## Provider compatibility

Each full lab uses a provider-aware `Vagrantfile` supporting KVM/QEMU with libvirt (primary, recommended on Linux) and VirtualBox (compatible Intel/AMD x86_64 hosts on Linux, macOS, or Windows).

| Lab | Linux x86_64 with libvirt | Intel/AMD x86_64 with VirtualBox | Apple Silicon / ARM64 |
|---|---|---|---|
| DevOps/DevSecOps Platform Lab | Supported | Supported | Not supported |
| Active Directory Security Lab | Supported | Supported | Not supported |
| Segmented Active Directory Lab | Supported | Supported | Not supported |
| Windows Server Hardening Lab (experimental) | Supported | Supported | Not supported |
| DevSecOps Lite — ARM64 | Not applicable | Not applicable | Planned |

> [!NOTE]
> **Supported** means the provider workflow is maintained and validated for the documented lab scope. It does not guarantee identical behavior across every host kernel, provider release, Vagrant plugin version, third-party Vagrant box revision, or hardware configuration.

### Apple Silicon status

Apple Silicon (ARM64) hosts are not currently supported or validated. The lab portfolio depends on x86_64 Windows guests, x86_64 Vagrant boxes and provider-specific behavior that have not been validated on ARM64. A separate **DevSecOps Lite — ARM64** profile is planned but not deployable, so Apple Silicon has no supported deployment path in this repository.

Host requirements, Vagrant plugins, and the full provider and Apple Silicon details are in [Platform support and prerequisites](./docs/setup/platform-support.md).

---

## Architecture overview

[![Enterprise Infrastructure Architecture](./assets/diagrams/architecture-overview.png)](./assets/diagrams/)

The lab environments deploy independently through provider-aware Vagrant configurations. The architecture combines isolated Active Directory environments, segmented virtual networks, Kubernetes workloads, security monitoring, policy enforcement, and validation workflows.

> [!NOTE]
> The DevOps/DevSecOps Platform Lab uses Ansible and Terraform/OpenTofu. The Active Directory and Windows Server Hardening labs are provisioned by Vagrant with shell and PowerShell provisioners, as is the DevOps lab's own VM build. The Active Directory labs ([base](./labs/security/active-directory/base/provision/), [segmented](./labs/security/active-directory/vlan-segmented/provision/)) and the [DevOps lab](./labs/infrastructure/devops-linux-lab/provision/) keep those scripts as files under `provision/`; the Windows Server Hardening lab currently embeds its provisioning logic in its `Vagrantfile`.
>
> See [Provisioning Philosophy](./docs/architecture/architecture.md#provisioning-philosophy) for the design rationale.

For architecture details, trust boundaries, and design decisions, see the [Architecture Overview](./docs/architecture/architecture.md), [Security Scope](./docs/security-scope.md), [Threat Model](./docs/architecture/threat-model.md), and [Emergency Isolation Runbook](./docs/architecture/emergency-isolation-runbook.md).

---

## What this project demonstrates

| Domain | Capabilities | Location |
|---|---|---|
| Active Directory security | Domain deployment, AD CS, identity attack-path simulation, privilege-escalation research, and post-compromise analysis workflows | `labs/security/active-directory/base/` |
| LLM application security | OWASP Top 10 for LLM Applications (2026), including a safety-sandboxed vulnerable and defensive training pair for each covered category | `labs/security/active-directory/base/llm-lab/` |
| Network segmentation | Logical segmentation boundaries, routing separation, trust relationships, and segmentation-aware security-testing scenarios | `labs/security/active-directory/vlan-segmented/` |
| DevOps/DevSecOps | Kubernetes operations, GitOps, observability, runtime security, and policy enforcement | `labs/infrastructure/devops-linux-lab/` |
| Defensive hardening | CIS-benchmark-inspired controls mapped to specific AD attack techniques, with validation tooling for each control | `labs/security/windows-hardening/` |
| Infrastructure as Code | Vagrant, Ansible, Bash, Python, and automation workflows | Repository-wide |
| Security documentation | Architecture, threat models, setup guides, troubleshooting, and learning paths | `docs/` |
| Validation and quality engineering | Python tests, Bash tests, linting, documentation checks, and CI workflows | `.github/`, `tests/`, and `scripts/` |

---

## Common workflows

Run these from the selected lab directory:

```bash
vagrant status              # lab state
vagrant up [<vm-name>]      # start or resume
vagrant provision [<vm>]    # re-run provisioning
vagrant halt                # stop, keeping disks and state
vagrant snapshot save <n>   # snapshots: save | list | restore | delete
vagrant destroy -f          # destroy the lab
```

> [!WARNING]
> `vagrant destroy -f` permanently removes the selected lab VMs and can remove provider-managed disks. Vagrant snapshots are provider-dependent and are not a substitute for exporting artifacts or maintaining external backups.

All commands, plus snapshot, reload and lab-manager examples, are in [Common workflows](./docs/guides/workflows/common-workflows.md). See also [Quickstart Examples](./docs/setup/quickstart-examples.md), the [Vagrant Management Tutorial](./docs/guides/infrastructure/vagrant-management-tutorial.md) and [Lab Reset and Cleanup](./docs/guides/workflows/lab-reset-and-cleanup.md).

---

## Troubleshooting

Most deployment issues are a hanging `vagrant up`, a VM created under the wrong provider, WinRM or SSH failures on Windows guests, stale network resources after an interrupted run, too little host CPU, memory or disk, or an unavailable box, mirror or image. Start with:

```bash
vagrant status
./scripts/check-prerequisites.sh --all
```

Step-by-step fixes are in the [Troubleshooting Guide](./docs/setup/troubleshooting.md), the [Segmented Lab Troubleshooting Guide](./labs/security/active-directory/vlan-segmented/docs/troubleshooting.md) and [Lab Reset and Cleanup](./docs/guides/workflows/lab-reset-and-cleanup.md).

---

## Documentation hub

| Document | Purpose |
|---|---|
| [Documentation Index](./docs/README.md) | Documentation map grouped by topic |
| [Learning Path](./docs/project/learning-path.md) | Recommended progression through the labs |
| [Architecture](./docs/architecture/architecture.md) | Infrastructure design and deployment architecture |
| [Security Scope](./docs/security-scope.md) | Security boundaries and intended use |
| [Threat Model](./docs/architecture/threat-model.md) | Threat-model documentation |
| [Emergency Isolation Runbook](./docs/architecture/emergency-isolation-runbook.md) | Emergency isolation procedures |
| [Roadmap](./docs/project/roadmap.md) | Planned improvements and future development |
| [Portfolio](./docs/project/portfolio.md) | Skills and competencies demonstrated |
| [Dependencies](./docs/dependencies.md) | Project dependencies and requirements |
| [Installation Guide](./docs/setup/installation.md) | Host and provider setup |
| [Quickstart Examples](./docs/setup/quickstart-examples.md) | Rapid deployment patterns |
| [Troubleshooting](./docs/setup/troubleshooting.md) | Common problems and solutions |
| [Platform support and prerequisites](./docs/setup/platform-support.md) | Provider matrix, Apple Silicon status, host requirements, Vagrant plugins |
| [Common workflows](./docs/guides/workflows/common-workflows.md) | Everyday Vagrant commands, snapshots and the lab manager |
| [Development](./docs/development.md) | Repository structure and development quickstart |
| [Known limitations](./docs/known-limitations.md) | Platform, lab-specific and validation limits |
| [Lab Reset and Cleanup](./docs/guides/workflows/lab-reset-and-cleanup.md) | Snapshot revert, VM rebuild, full teardown, and host network cleanup |
| [Minimal Resource Deployment](./docs/guides/optimization/minimal-resource-deployment.md) | Reduced-resource deployment guidance |
| [Guides](./docs/guides/) | Security, infrastructure, and deployment guides |
| [Scripts](./scripts/) | Host-readiness and validation helpers |

---

## Development

```bash
python3 -m pip install -r requirements-dev.txt
pre-commit install
make lint test validate security docs-refs   # run `make help` for every target
```

The repository layout, all `make` targets and the contributor workflow are in [Development](./docs/development.md) and [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## Project maturity

The repository is actively developed and includes automated quality checks, documentation validation, and selected provider workflow validation.

Deployment outcomes can still vary by host hardware, operating system, virtualization provider, Vagrant plugin version, guest image revision, and selected lab profile. Review each lab README for its current validation status, supported profiles, provider requirements, and known limitations.

---

## Contributing

Contributions are welcome.

Before submitting a contribution:

- Open an issue before making major changes
- Keep pull requests focused
- Update documentation when required
- Add or update tests for behavioral changes
- Run relevant lint, test, validation, and documentation checks
- Do not include credentials, secrets, private keys, or sensitive host information
- Follow the repository contribution guidelines

For ARM64 work, include architecture compatibility evidence, image and chart validation results, provider documentation, automated tests where practical, and a clear statement of unsupported features.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the complete contributor workflow.

---

## Security and ethics

This project is intended only for:

- Education
- Authorized security research
- Defensive security practice
- Isolated laboratory environments
- Testing systems owned by the operator or explicitly authorized for testing

Only test systems that you own or have explicit permission to assess.

Unauthorized access, testing, scanning, exploitation, credential attacks, or lateral movement against external systems is prohibited.

Intentionally vulnerable workloads and authorized security-test scenarios must remain isolated from production networks and systems.

For additional security information, see:

- [Security Scope](./docs/security-scope.md)
- [Threat Model](./docs/architecture/threat-model.md)
- [SECURITY.md](SECURITY.md)

---

## Known limitations

- Full-profile deployments may need 32 GB or more host RAM and about 200 GB of free disk, depending on the lab and provider.
- KVM/QEMU with libvirt needs a Linux host; VirtualBox targets Intel/AMD x86_64. Apple Silicon / ARM64 has no supported deployment path.
- Windows-based labs use Microsoft evaluation media; you are responsible for complying with the Microsoft licensing terms.
- The Windows Server Hardening Lab is an experimental `v0.1.0` MVP.
- The LLM lab's injection filter is heuristic and its offline mock model is deliberately gullible, so results with a real model differ.
- CI builds and boots the LLM lab container but does not boot any VM or deploy every environment on every push.

See [Known limitations](./docs/known-limitations.md) for the complete list.

---

## License

This project is licensed under the MIT License.

See [LICENSE](./LICENSE) for the full license text.

Copyright © 2023–2026 Miguel A. Carlo

# Documentation index

This is a map of every doc in `docs/`, grouped by folder. Start here if
you're not sure where to look.

## Getting started

| Doc | What it covers |
|---|---|
| [`project/learning-path.md`](project/learning-path.md) | **Start here.** Which lab to try first, and in what order |
| [`setup/installation.md`](setup/installation.md) | Host setup, prerequisites, deploying any of the three labs |
| [`setup/troubleshooting.md`](setup/troubleshooting.md) | Common setup and runtime issues |
| [`setup/quickstart-examples.md`](setup/quickstart-examples.md) | Worked setup examples |
| [`guides/optimization/minimal-resource-deployment.md`](guides/optimization/minimal-resource-deployment.md) | Running any of the three labs on smaller hosts |
| [`dependencies.md`](dependencies.md) | Supported OS, Python/Kubernetes versions, external tool and package dependencies |

## Architecture

| Doc | What it covers |
|---|---|
| [`architecture/architecture.md`](architecture/architecture.md) | Overall infrastructure design for all three labs |
| [`architecture/threat-model.md`](architecture/threat-model.md) | Assets, trust boundaries, and assumed attacker per lab |
| [`architecture/emergency-isolation-runbook.md`](architecture/emergency-isolation-runbook.md) | What to do if a lab reaches the internet or a trusted network unexpectedly |
| [`security-scope.md`](security-scope.md) | What's authorized/isolated for the offensive-security content |

## Workflows

| Doc | What it covers |
|---|---|
| [`guides/workflows/workflows.md`](guides/workflows/workflows.md) | General repo/lab workflows |
| [`guides/workflows/lab-deployment-workflow.md`](guides/workflows/lab-deployment-workflow.md) | Step-by-step lab deployment flow |
| [`guides/workflows/lab-reset-and-cleanup.md`](guides/workflows/lab-reset-and-cleanup.md) | Snapshot revert, VM rebuild, full teardown, and host network cleanup |

## Infrastructure guides

| Doc | What it covers |
|---|---|
| [`guides/infrastructure/devops-platform-overview.md`](guides/infrastructure/devops-platform-overview.md) | Standalone tutorial (not this repo's lab): Vagrant → Docker → Minikube → Jenkins → Prometheus/Grafana |
| [`guides/infrastructure/complete-devops-platform-guide.md`](guides/infrastructure/complete-devops-platform-guide.md) | Standalone tutorial (not this repo's lab): adds Terraform, k3d, ArgoCD/GitOps, image scanning, canary deployments |
| [`guides/infrastructure/kubernetes-security-hardening.md`](guides/infrastructure/kubernetes-security-hardening.md) | k3s cluster hardening |
| [`guides/infrastructure/ansible-automation.md`](guides/infrastructure/ansible-automation.md) | Hands-on Ansible practice guide for the lab's Linux nodes (lab provisioning itself still uses Vagrant shell provisioners; see [`roadmap.md`](project/roadmap.md)) |
| [`guides/infrastructure/vagrant-management-tutorial.md`](guides/infrastructure/vagrant-management-tutorial.md) | Vagrant commands and workflows |
| [`guides/infrastructure/managing-kvm-qemu-cli-tutorial.md`](guides/infrastructure/managing-kvm-qemu-cli-tutorial.md) | KVM/QEMU CLI reference |
| [`guides/infrastructure/proxmox-host-setup.md`](guides/infrastructure/proxmox-host-setup.md) | Running the host virtualization layer on Proxmox |

## Security guides

| Doc | What it covers |
|---|---|
| [`guides/security/security-tooling-reference.md`](guides/security/security-tooling-reference.md) | Tooling reference used across the AD pentest lab |
| [`guides/security/password-attacks.md`](guides/security/password-attacks.md) | Password attack techniques and lab usage |
| [`guides/security/metasploit-lab-guide.md`](guides/security/metasploit-lab-guide.md) | Metasploit usage in the lab |
| [`guides/security/network-traffic-analysis.md`](guides/security/network-traffic-analysis.md) | Traffic analysis / packet capture workflows |
| [`guides/security/detection-and-blue-team.md`](guides/security/detection-and-blue-team.md) | Blue-team detection content (SIEM, alerting) |
| [`guides/security/domain-compromise-walkthrough.md`](guides/security/domain-compromise-walkthrough.md) | End-to-end domain compromise walkthrough for the AD Pentest Lab |
| [`guides/security/ad-mitre-log-source-playbook.md`](guides/security/ad-mitre-log-source-playbook.md) | Mapping AD log sources to MITRE ATT&CK |
| [`guides/security/llm-security-compliance-lab.md`](guides/security/llm-security-compliance-lab.md) | LLM platform vulnerability/compliance testing |

## Project

| Doc | What it covers |
|---|---|
| [`project/portfolio.md`](project/portfolio.md) | Portfolio-style project summary |
| [`project/roadmap.md`](project/roadmap.md) | Planned improvements and future lab development |

---

Looking for lab-specific docs (attack guides, credentials, networking) instead of general repo docs? Those live alongside each lab:

- `labs/security/active-directory/base/docs/`
- `labs/security/active-directory/vlan-segmented/docs/`
- `labs/infrastructure/devops-linux-lab/docs/`

See [`labs/README.md`](../labs/README.md) for the full lab index.

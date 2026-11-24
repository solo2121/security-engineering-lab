# Portfolio Index

**Status:** Active &nbsp;|&nbsp; **Last Updated:** 2026-11-21

**Maintainer:** Miguel A. Carlo ([@solo2121](https://github.com/solo2121))

---

## Labs

| Lab | Path | Focus |
|-----|------|-------|
| Active Directory Pentest Lab | [`labs/security/active-directory/base/`](../../labs/security/active-directory/base/) | Kerberos attacks, AD CS ESC1/4/7/8/9 chains, privilege escalation, and NTLM relay |
| VLAN Enterprise Lab | [`labs/security/active-directory/vlan-segmented/`](../../labs/security/active-directory/vlan-segmented/) | Network segmentation, VLAN isolation, enterprise routing, and traffic analysis |
| DevOps Linux Lab | [`labs/infrastructure/devops-linux-lab/`](../../labs/infrastructure/devops-linux-lab/) | Kubernetes (k3s, Kind, K3d), Argo CD, Harbor, Terraform, OpenTofu, and the Prometheus/Grafana/Loki stack |
| Windows Server Hardening Lab (experimental) | [`labs/security/windows-hardening/`](../../labs/security/windows-hardening/) | Windows Server hardening with selectable profiles; advanced controls such as LAPS and Sysmon + WEF are experimental (v0.1.0) |
| OWASP LLM Training Lab | [`labs/security/active-directory/base/llm-lab/`](../../labs/security/active-directory/base/llm-lab/) | Scenarios for the OWASP Top 10 for LLM Applications, each with documented mitigations and tests |

---

## Security Tooling

| Component | Path | Purpose |
|-----------|------|---------|
| Audit | [`tools/security/audit/`](../../tools/security/audit/) | Cisco switch audit tooling |
| Network | [`tools/security/network/`](../../tools/security/network/) | Traffic analysis, firewall scanning, and topology mapping |
| Exploitation | [`tools/security/exploitation/`](../../tools/security/exploitation/) | Educational offensive tooling and post-exploitation workflows |
| Reconnaissance | [`tools/security/reconnaissance/`](../../tools/security/reconnaissance/) | Nmap automation, Amass OSINT, and port scanning |
| Wireless | [`tools/security/wireless/`](../../tools/security/wireless/) | Wireless lab tooling and evil-twin experimentation |

---

## System Administration

| Component | Path | Purpose |
|-----------|------|---------|
| Monitoring | [`tools/sysadmin/monitoring/`](../../tools/sysadmin/monitoring/) | Log analysis and system/security monitoring |
| System Hardening | [`tools/sysadmin/system-hardening/`](../../tools/sysadmin/system-hardening/) | ClamAV, rootkit scanning, and user/network audits |
| Utilities | [`tools/sysadmin/utilities/`](../../tools/sysadmin/utilities/) | Timeshift, UFW, BIND, memory cleanup, and Git management |

---

## Key Techniques by Domain

### Active Directory
- ESC8 → NTLM relay → domain compromise.
- Kerberoasting and AS-REP roasting.
- BloodHound attack-path enumeration via LDAP.
- DCSync and credential theft.
- ACL abuse and Group Policy exploitation.
- Token impersonation.
- ZeroLogon (`CVE-2020-1472`) and PetitPotam (`CVE-2021-36942`).
- NoPac (`CVE-2021-42287`) and Resource-Based Constrained Delegation (`RBCD`).
- PrintNightmare (`CVE-2021-1675` / `CVE-2021-34527`).

### Cloud
- AWS IAM privilege escalation through LocalStack simulation.
- S3 bucket enumeration and data exfiltration.
- EC2 metadata service exploitation.

### AI / LLM Security
- Prompt injection and jailbreaking.
- RAG poisoning.
- Token bombing and denial-of-service testing.
- Function call injection.
- Embedding inversion.

Implemented as OWASP Top 10 for LLM Applications scenarios in [`llm-lab/`](../../labs/security/active-directory/base/llm-lab/); attack walkthroughs are in the [AD lab attack guide](../../labs/security/active-directory/base/docs/attack-guide.md).

### Detection Engineering
- MITRE ATT&CK-aligned detection guidance, log sources, and detection ideas for each attack phase ([`ad-mitre-log-source-playbook.md`](../guides/security/ad-mitre-log-source-playbook.md)).
- Per-technique evidence, Windows Security/Sysmon event IDs, and example detection logic ([`detection-and-blue-team.md`](../guides/security/detection-and-blue-team.md)).
- Windows Event Log and Sysmon pipeline analysis.
- Detection gap analysis exercises across simulated attack chains.

### Infrastructure & DevSecOps
- Multi-VM enterprise lab provisioning with Vagrant and KVM/QEMU.
- Kubernetes cluster deployment with k3s, Kind, and K3d.
- GitOps with Argo CD.
- Infrastructure as Code with Terraform and OpenTofu.
- Container registry management with Harbor and airgap image seeding.

---

## Evidence in This Repository

Pointers a reviewer can inspect directly. Nothing here claims more than these files show.

| What | Where |
|------|-------|
| CI pipeline (lint, shell and Python checks, secret-scan baseline, Vagrantfile validation, tests) | [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) |
| Automated tests | [`tests/`](../../tests/) |
| Demo recordings | [`assets/demos/`](../../assets/demos/) |
| Lab scope, isolation, and responsible-use rules | [`docs/security-scope.md`](../security-scope.md) and [`SECURITY.md`](../../SECURITY.md) |
| Intentional lab credentials, documented as lab-only | [`lab-credentials.md`](../../labs/security/active-directory/base/docs/lab-credentials.md) |
| Defensive counterpart to the attack guides | [`detection-and-blue-team.md`](../guides/security/detection-and-blue-team.md) |

---

## Documentation

For the full documentation index, see [`docs/README.md`](../README.md).

---

## Suggested Exploration Path

1. [`labs/infrastructure/devops-linux-lab/README.md`](../../labs/infrastructure/devops-linux-lab/README.md) — start with the base infrastructure.
2. [`labs/security/active-directory/base/README.md`](../../labs/security/active-directory/base/README.md) — move into the core offensive security environment.
3. [`labs/security/active-directory/base/llm-lab/README.md`](../../labs/security/active-directory/base/llm-lab/README.md) and [`docs/guides/security/detection-and-blue-team.md`](../guides/security/detection-and-blue-team.md) — explore the LLM security scenarios and the defensive detection guidance.
4. [`docs/architecture/architecture.md`](../../docs/architecture/architecture.md) — review the full system design.

---

## Skills and Role Mapping

| Role | Relevant Lab | Skills Practiced |
|------|-------------|-----------------|
| Penetration Tester | `labs/security/active-directory/base/` | AD enumeration, exploitation, privilege escalation |
| Red Team Operator | `labs/security/active-directory/vlan-segmented/` | Adversary emulation, lateral movement, and the detection evidence it leaves |
| Security Engineer | `labs/security/active-directory/base/llm-lab/` + `docs/guides/security/` | OWASP LLM Top 10 scenarios, detection guidance, log analysis |
| Cloud Security Engineer | `labs/security/active-directory/vlan-segmented/` | AWS IAM abuse, S3 enumeration, EC2 metadata attacks |
| DevSecOps Engineer | `labs/infrastructure/devops-linux-lab/` | Falco, Kyverno, Cert-Manager, Argo CD, Harbor |
| Kubernetes Engineer | `labs/infrastructure/devops-linux-lab/` | k3s, Kind, K3d, Helm, GitOps workflows |
| Linux Systems Administrator | `tools/sysadmin/` + Linux lab nodes | Hardening, monitoring, troubleshooting |

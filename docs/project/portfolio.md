# Portfolio Index

**Status:** Active &nbsp;|&nbsp; **Last Updated:** 2026-07-08

---

## Labs

| Lab | Path | Focus |
|-----|------|-------|
| Active Directory Pentest Lab | [`labs/security/active-directory/base/`](../../labs/security/active-directory/base/) | Kerberos attacks, AD CS ESC1/4/7/8/9 chains, privilege escalation, and NTLM relay |
| VLAN Enterprise Lab | [`labs/security/active-directory/vlan-segmented/`](../../labs/security/active-directory/vlan-segmented/) | Network segmentation, VLAN isolation, enterprise routing, and traffic analysis |
| DevOps Linux Lab | [`labs/infrastructure/devops-linux-lab/`](../../labs/infrastructure/devops-linux-lab/) | Kubernetes (k3s, Kind, K3d), Argo CD, Harbor, Terraform, OpenTofu, and the Prometheus/Grafana/Loki stack |

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
- Chain-of-thought leakage.
- Embedding inversion.

### Detection Engineering
- MITRE ATT&CK-aligned detection rules.
- Windows Event Log and Sysmon pipeline analysis.
- Threat visibility gap analysis across simulated attack chains.

### Infrastructure & DevSecOps
- Multi-VM enterprise lab provisioning with Vagrant and KVM/QEMU.
- Kubernetes cluster deployment with k3s, Kind, and K3d.
- GitOps with Argo CD.
- Infrastructure as Code with Terraform and OpenTofu.
- Container registry management with Harbor and airgap image seeding.

---

## Documentation

For the full documentation index, see [`docs/README.md`](../README.md).

---

## Suggested Exploration Path

1. [`labs/infrastructure/devops-linux-lab/README.md`](../../labs/infrastructure/devops-linux-lab/README.md) — start with the base infrastructure.
2. [`labs/security/active-directory/base/README.md`](../../labs/security/active-directory/base/README.md) — move into the core offensive security environment.
3. [`tools/security/audit/`](../../tools/security/audit/) — explore the LLM and detection tooling layer.
4. [`docs/architecture/architecture.md`](../../docs/architecture/architecture.md) — review the full system design.

---

## Skills and Role Mapping

| Role | Relevant Lab | Skills Practiced |
|------|-------------|-----------------|
| Penetration Tester | `labs/security/active-directory/base/` | AD enumeration, exploitation, privilege escalation |
| Red Team Operator | `labs/security/active-directory/vlan-segmented/` | Adversary emulation, lateral movement, C2 concepts |
| Security Engineer | `tools/security/audit/` | LLM security, detection engineering, log analysis |
| Cloud Security Engineer | `labs/security/active-directory/vlan-segmented/` | AWS IAM abuse, S3 enumeration, EC2 metadata attacks |
| DevSecOps Engineer | `labs/infrastructure/devops-linux-lab/` | Falco, Kyverno, Cert-Manager, Argo CD, Harbor |
| Kubernetes Engineer | `labs/infrastructure/devops-linux-lab/` | k3s, Kind, K3d, Helm, GitOps workflows |
| Linux Systems Administrator | `tools/sysadmin/` + Linux lab nodes | Hardening, monitoring, troubleshooting |

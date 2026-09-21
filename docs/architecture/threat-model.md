# Threat Model

This document describes the assets, trust boundaries, and assumed attacker capabilities for each lab in security-engineering-lab. It exists to make explicit *why* each lab is vulnerable the way it is, rather than leaving that to be inferred from the Vagrantfiles.

For legal/ethical scope (who is authorized to run this, and how), see [`../security-scope.md`](../security-scope.md). This document is about attack surface and trust boundaries, not authorization.

---

## Methodology

Each lab below is modeled the same way:

- **Assets** — what an attacker inside the lab is ultimately after.
- **Trust boundaries** — where isolation is enforced, and where it isn't.
- **Assumed attacker** — starting position, capabilities, and goal. None of these labs model an attacker with no starting foothold; each assumes the attacker already has a specific, stated level of access.
- **Attack surface** — the specific, implemented techniques available (not a wishlist — everything listed here is a real, working scenario in the Vagrantfile).
- **Explicitly out of scope** — what this lab does not model, so it isn't mistaken for a gap.

---

## Lab 1 — Active Directory Pentest Lab (flat network)

**Assets:** Domain Admin credentials on `dc01`; the `LAB-ESC-CA` certificate authority on `ca01-esc`; SQL data on `db01`; the LLM API keys/data on `llm01`; the simulated AWS credentials/Terraform state on `cloud-pentest`.

**Trust boundaries:** All 11 hosts share a single flat `172.28.128.0/24` network — there is no internal segmentation in this lab by design (that's what Lab 2 adds). The only boundary that exists is between this internal network and the outside world: it's NAT-isolated from the real internet, and isolated from the other two labs (each lab is its own libvirt network with no bridging between them).

**Assumed attacker:** Starts as `kali`, an already-present box on the same flat network with no credentials — i.e., this models an attacker who has already gained a foothold on the internal network (e.g., a compromised workstation or a dropped implant), not an external attacker breaching the perimeter. Perimeter breach is out of scope for this lab.

**Attack surface (implemented, not aspirational):**
- Kerberoasting, AS-REP roasting, GPP credential extraction
- ZeroLogon (CVE-2020-1472), PetitPotam, NoPac, PrintNightmare
- Resource-Based Constrained Delegation, Shadow Credentials
- AD CS abuse: ESC1, ESC4, ESC7, ESC8, ESC9 against `LAB-ESC-CA`
- gMSA password readable by Domain Users; ADIDNS wildcard record writable by any authenticated user
- OWASP Top 10 for LLM Applications (LLM01–LLM10) vulnerable endpoints on `llm01`, plus two legacy supplemental scenarios: prompt injection, RAG poisoning, embedding inversion
- Exposed Terraform state (`cloud-pentest`) simulating leaked AWS credentials via LocalStack
- CVE-2021-3560 (Polkit) local privilege escalation on `linux01`
- `metasploitable2` and `juice-shop` as standalone, unauthenticated external-style targets

**Explicitly out of scope:** initial external compromise (phishing, perimeter exploitation), physical access, attacks against the Vagrant/libvirt host itself, multi-host or distributed attack scenarios (see Known Limitations in the root README).

---

## Lab 2 — AD Pentest VLAN / Enterprise Segmentation Lab

**Assets:** Same as Lab 1 — this lab reimplements an equivalent attack surface across its own 12-host VLAN-segmented inventory (which also adds an `opnsense` router/firewall VM not present in Lab 1). The asset that's *added* is the segmentation itself: proving lateral movement across VLAN boundaries, not just within one flat network.

**Trust boundaries:** Five isolated libvirt networks (VLAN 10 – management/AD, VLAN 20 – workstations, VLAN 30 – servers, VLAN 40 – DMZ, VLAN 99 – attacker), each `libvirt__forward_mode: "none"` — meaning libvirt itself does not route between them. `kali` is deliberately given reachability into all four target VLANs for recon/exercise purposes; this is a **lab convenience, not a modeled router or firewall**. There is no real Layer-3 device in this lab standing between VLANs the way there would be in a production network — see the note in each lab's own README.

**Assumed attacker:** Same starting position as Lab 1 (already has a foothold, this time specifically on VLAN 99). The goal is the same (Domain Admin on `dc01`), but the model now requires reasoning about which VLAN a given technique is possible from, not just whether it's possible at all.

**Attack surface:** Everything in Lab 1, plus:
- VLAN enumeration and inter-segment pivoting
- Reasoning about which attacks are VLAN-local vs. require crossing a segment boundary

**Explicitly out of scope:** a real router/firewall with actual ACL enforcement (this lab tests AD attacks *across* a segmented topology, not firewall/ACL evasion against a real network device); anything already out of scope for Lab 1.

---

## Lab 3 — DevOps / DevSecOps Lab

**Assets:** The k3s cluster's ability to run arbitrary workloads (the thing every scenario below tries to abuse); the Harbor container registry and its image supply chain; the CI/CD pipeline itself (Gitea source control, Jenkins automation, SonarQube/Gitleaks/Trivy scanning stages) on the `cicd-server` VM; secrets mounted into cluster workloads or held in Vault; the integrity of Kyverno admission policies and Falco runtime alerting (i.e., can a workload evade or disable the controls meant to catch it).

**Trust boundaries:** All 12 hosts sit on a single network (`192.168.121.0/24` by default, auto-detected from the host's libvirt configuration — see [`devops-linux-lab/README.md`](../../labs/infrastructure/devops-linux-lab/README.md) for the profile-gated deployment options). The meaningful trust boundary in this lab isn't network segmentation — it's **inside vs. outside the k3s cluster**, and **inside vs. outside an individual container**. Harbor, ArgoCD, Prometheus, Grafana, Loki, Falco, and Kyverno all run as workloads on the cluster, not as separate VMs. The CI/CD server (`cicd-server`) is the one exception — Gitea, Jenkins, SonarQube, Vault, and ZAP run as Docker containers on a standalone VM, not inside the k3s cluster.

**Assumed attacker:** Two distinct profiles, deliberately different from the AD labs:
1. A malicious or compromised **supply-chain artifact** — a backdoored container image that reaches the registry or cluster.
2. An operator with `kubectl`/registry access practicing **defense** — using Falco, Kyverno, and Trivy to detect and block (1) rather than only exploit it.

This lab is bidirectional by design: it's as much a defensive/detection-engineering lab as an offensive one.

**Attack surface:**
- Backdoored container images and image-poisoning scenarios via Harbor
- Secret leaks and insecure Kubernetes deployment manifests
- Supply-chain attack simulation (image built with a hidden payload, pushed, deployed)
- Policy-enforcement testing: does a Kyverno policy actually block the insecure deployment, or only warn
- Runtime detection testing: does Falco actually alert on the anomalous behavior once the workload is running

**Explicitly out of scope:** multi-cluster or multi-tenant Kubernetes attacks, cloud-provider-specific IAM misconfigurations (that scenario lives in Lab 1's `cloud-pentest`/LocalStack setup, not here), attacks against the underlying host OS or libvirt itself.

---

## Repository-wide assumptions

These apply to all three labs and are stated once here rather than repeated per-lab:

- **The physical/virtualization host is fully trusted.** No lab models an attacker who has already compromised the KVM/libvirt host itself — if that trust boundary fails, every VM in every lab is trivially compromised, and that's considered outside what these labs are testing.
- **Upstream Vagrant boxes are trusted.** These labs do not model supply-chain compromise of the base box images themselves (e.g., a tampered `kalilinux/rolling` box). Box versions are pinned only for some images (for example Kali, Metasploitable2, and the Ubuntu boxes in the base lab); the Windows evaluation boxes, most boxes in the segmented lab, and the DevOps lab's `bento/*` boxes follow the latest published release. Where pinning exists it is for reproducibility, not as a supply-chain control.
- **No lab is exposed to the real internet.** All three are NAT-isolated by design; none of this attack surface is reachable outside the host running Vagrant. Real-world initial-access techniques (phishing, external perimeter breach) are not modeled anywhere in this repository.
- **Single-host deployment only.** No lab supports or models a distributed, multi-host attack surface.

For what's simulated vs. real at the service level (e.g., which Windows features are genuinely licensed vs. evaluation-mode, where CI does and doesn't validate runtime behavior), see **Known Limitations** in the root [`README.md`](../../README.md#known-limitations).

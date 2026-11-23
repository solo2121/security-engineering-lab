# Security Labs

This directory contains enterprise-focused Active Directory penetration testing and security practice environments, plus a defensive counterpart lab.

---

## Available Labs

| Lab                    | Path                             | Focus                                                                                                                     | Version                                                | Hosts |
|------------------------|----------------------------------|---------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------|-------|
| Active Directory Lab   | [`active-directory/base/`](active-directory/base/)     | Complete AD attack chain from recon to Domain Admin; Kerberos attacks, AD CS exploits, lateral movement, cloud and LLM attacks | v1.13 – Enterprise Edition (FLAT NETWORK – OPTIMIZED) | up to 11 (`LAB_PROFILE=full`); 6 by default |
| VLAN Enterprise AD Lab | [`active-directory/vlan-segmented/`](active-directory/vlan-segmented/) | Multi-subnet enterprise topology with VLAN segmentation, routing, inter-VLAN attacks, and network isolation testing       | v2.1.5                                                 | up to 12 (`LAB_PROFILE=full`); auto-detected by default |
| Windows Server Hardening Lab (experimental) | [`windows-hardening/`](windows-hardening/) | Defensive counterpart to the AD Pentest Lab — CIS-benchmark-inspired hardening baseline, each control mapped to the AD pentest attack technique it mitigates | v0.1.0 (MVP) | up to 2 (`LAB_PROFILE=full`); 1 by default |

The two AD pentest labs and the hardening lab are all `LAB_PROFILE`-scoped: `vagrant up` with no profile set only creates a subset of VMs sized for the host, not every machine listed above. See each lab's own README for its profile table.

---

## Quick Start

### AD Pentest Lab

```bash
cd active-directory/base
vagrant up
python3 scripts/vagrant_manager.py
vagrant status
```

**First attack:** Kerberoasting (low-priv initial access)

```bash
bloodhound-python -u vagrant -p Vagrant123! -d lab.local -dc 172.28.128.21 -c All -o ~/recon/
```

### VLAN Enterprise Lab

```bash
cd active-directory/vlan-segmented
vagrant up
python3 scripts/vagrant_manager.py
vagrant status
```

**First task:** Validate routing and basic reachability from the attacker VM

```bash
ip route
ping 172.28.10.21
```

For full VLAN topology and subnets, see [`active-directory/vlan-segmented/README.md`](active-directory/vlan-segmented/README.md).

---

## Lab Architecture (AD Pentest Lab)

The **flat AD Pentest Lab** uses a shared `172.28.128.0/24` network with 11 hosts:

| Host            | IP             | OS                    | Lab Use                      |
|-----------------|----------------|------------------------|------------------------------|
| kali            | 172.28.128.10  | Kali Linux             | Attacker position            |
| metasploitable2 | 172.28.128.12  | Ubuntu 8.04            | Legacy exploitation target   |
| juice-shop      | 172.28.128.15  | Node.js (Ubuntu base)  | OWASP web app                |
| dc01            | 172.28.128.21  | Windows Server 2022    | Domain Controller            |
| db01            | 172.28.128.23  | Windows Server 2022    | SQL Server                   |
| ca01-esc        | 172.28.128.25  | Windows Server 2022    | AD CS (ESC attack surface)   |
| win10           | 172.28.128.30  | Windows 10             | Domain workstation           |
| llm01           | 172.28.128.60  | Ubuntu 22.04           | LLM endpoints                |
| linux01         | 172.28.128.72  | Ubuntu 22.04           | Linux member server          |
| print01         | 172.28.128.73  | Windows Server 2022    | Print server (PrintNightmare)|
| cloud-pentest   | 172.28.128.80  | Ubuntu 22.04           | LocalStack AWS simulation    |
| (infra)         | varies         | libvirt/KVM network    | Virtual networking fabric    |

> The VLAN Enterprise Lab uses a different, **VLAN-segmented** addressing scheme documented in its own README.

---

## Key Credentials (Seeded for Learning)

These credentials are intentionally weak and reused across services for training purposes.

| Account        | Password        | Type            | Lab Use                          |
|----------------|-----------------|-----------------|----------------------------------|
| vagrant        | Vagrant123!     | Domain user     | Initial low-priv access          |
| svc_kerberoast | ServiceP@ss2    | Service account | Kerberoasting target             |
| svc_asrep      | ServiceP@ss1    | Service account | AS-REP roasting target           |
| administrator  | Passw0rd!       | Domain Admin    | Final escalation goal            |
| alice.brown    | GPOP@ss789!     | Domain user     | AD CS ESC4 path                  |
| svc_caadmin    | CaAdminP@ss1    | Service account | CA administration                |
| svc_sql        | SqlSvcPass123!  | Service account | SQL Server abuse                 |

See each lab’s `docs/lab-credentials.md` for the full credential reference and role descriptions.

---

## Attack Paths

### AD Pentest Lab — Recommended Chain

**Goal: Zero credentials → Domain Admin**

1. **Recon** – nmap, SMB enumeration, DNS zone transfer.
2. **BloodHound** – map AD structure and identify shortest paths.
3. **Kerberoasting** – request and crack service tickets to recover `svc_kerberoast`.
4. **AD CS ESC1/ESC4** – abuse certificate templates to obtain a DA-equivalent certificate.
5. **DCSync** – pull all domain hashes (including `krbtgt`) for full persistence.

**Estimated time:** 30–60 minutes once the lab is up.

See [`active-directory/base/docs/attack-guide.md`](active-directory/base/docs/attack-guide.md) for all techniques and variations.

### VLAN Enterprise Lab — Network Isolation & Lateral Movement

**Goal: Understand and test multi-VLAN constraints**

1. Validate VLAN segmentation (identify which hosts live on which VLANs).
2. Confirm inter-VLAN routing and firewall rules from the attacker VLAN.
3. Attempt cross-VLAN lateral movement while respecting firewall policy.
4. Practice network isolation troubleshooting and misconfiguration abuse.

See [`active-directory/vlan-segmented/README.md`](active-directory/vlan-segmented/README.md) and `docs/attack-guide.md` in that directory for VLAN-specific details.

---

## Documentation by Lab

### AD Pentest Lab (`active-directory/base/`)

- **`README.md`** – Lab overview, setup, prerequisites.
- **`docs/attack-guide.md`** – Complete attack reference (14+ sections).
- **`docs/lab-credentials.md`** – All seeded credentials and service accounts.
- **`docs/dc01-deployment-validation.md`** – Recorded validation of a successful `dc01` deployment (static IP, AD promotion, scenario configuration).
- **`Vagrantfile`** – Lab definition (v1.14 – FLAT NETWORK – PROFILE-BASED), unified for both KVM/libvirt and VirtualBox (select with `--provider`).
- **`provision/`** – The PowerShell and shell scripts each VM runs, kept as reviewable files.
- **`scripts/lab_attack_automation.py`** – Optional automated attack chain.

### VLAN Enterprise Lab (`active-directory/vlan-segmented/`)

- **`README.md`** – Lab overview, VLAN topology, setup guide.
- **`docs/attack-guide.md`** – VLAN-specific attack paths and scenarios.
- **`docs/lab-credentials.md`** – Credentials for the VLAN environment.
- **`Vagrantfile`** – Lab definition with VLAN configuration (v2.1.6), unified for both KVM/libvirt and VirtualBox (select with `--provider`).
- **`provision/`** – The scripts each VM runs (OPNsense, Windows, Linux), kept as reviewable files.

---

## Prerequisites

Before starting either lab:

- **Host OS:** Linux with hardware virtualization (KVM/QEMU). Alternatively, any VirtualBox-supported x86_64 host (macOS, Windows, or Linux) — both labs select the provider from their single `Vagrantfile` via `--provider=virtualbox`; see each lab's README "VirtualBox Provider" section.
- **Vagrant:** Latest version with `vagrant-libvirt` and `vagrant-reload` plugins (libvirt); or just Vagrant + `vagrant-reload`/`vagrant-winrm` for VirtualBox, since the VirtualBox provider ships built in.
- **RAM:** 16 GB minimum (8 GB can run a reduced profile, but will be slow).
- **Disk:** 100 GB free (each lab uses ~40–50 GB).
- **Tools (preinstalled inside the Kali VM):**
  - `impacket`, `certipy-ad`, `bloodhound-python`, `netexec`
  - `kerbrute`, `responder`, `hashcat`

See [`../../docs/setup/installation.md`](../../docs/setup/installation.md) for detailed host setup instructions.

---

## Common Workflows

### Reset a Lab

```bash
cd active-directory/base   # or active-directory/vlan-segmented
vagrant destroy -f
vagrant up
```

### Run Only One VM

```bash
cd active-directory/base
vagrant up dc01
# or
vagrant up kali
```

### Clean Up Local Artifacts (example workflow)

```bash
rm -f /tmp/*.ccache /tmp/*.pfx /tmp/*.hashes
tar -czf ~/lab_backup_$(date +%Y%m%d).tar.gz ~/lab/
```

Adjust paths to match your environment if you store notes or loot elsewhere.

---

## Learning Progression

**Recommended order:**

1. **Start with AD Pentest Lab**
   - Bring the lab up and run the documented attack chain.
   - Read and understand each phase (Kerberoasting, AD CS, DCSync).
   - Manually reproduce one phase using your own commands.

2. **Explore Alternative Paths**
   - Use AD CS ESC4 instead of ESC1.
   - Try NTLM relay or RBCD-based paths.
   - Practice blue-team style detection and log review.

3. **Move to VLAN Enterprise Lab**
   - Reason about segmentation, routing, and firewall rules.
   - Attempt cross-VLAN lateral movement and isolation bypass.
   - Validate your assumptions with packet captures and routing tables.

4. **Combine for Portfolio/Practice**
   - Document full attack chains end-to-end.
   - Capture screenshots or notes for your portfolio or interview prep.
   - Iterate on hardening scenarios and re-attack.

---

## Safety and Ethics

These labs are **intentionally vulnerable** and are designed for:

- Authorized security training and skill development.
- Home lab practice on your own hardware.
- Internal corporate training in isolated environments.
- Interview and assessment preparation.

**Do not:**

- Expose lab services on public networks.
- Reuse lab credentials on real systems.
- Run these techniques against systems you do not own or control.

See [`../../docs/security-scope.md`](../../docs/security-scope.md) for a full security boundary discussion.

---

## Troubleshooting

### Vagrant Fails or VMs Won’t Start

```bash
vagrant validate
vagrant status
vagrant destroy -f && vagrant up
```

### VM Networking Issues

```bash
# Check libvirt networks on the host
sudo virsh net-list --all

# From inside a VM, basic connectivity checks
ping 172.28.128.21
```

### Out of Memory

Run only one lab at a time, or reduce per-VM memory in the `Vagrantfile`:

```ruby
config.vm.provider :libvirt do |libvirt|
  libvirt.memory = 2048  # reduce from 4096 if needed
end
```

### Kali Tools Missing

If tools did not install correctly inside the Kali VM:

```bash
vagrant ssh kali
pip3 install impacket certipy-ad bloodhound netexec
```

For more host-level troubleshooting, see [`../../docs/setup/troubleshooting.md`](../../docs/setup/troubleshooting.md).

---

## Contributing

To improve a security lab:

1. Test your changes locally (bring the lab up and run at least one full attack path).
2. Update the relevant `README.md` and `docs/attack-guide.md`.
3. Ensure the `Vagrantfile` passes `vagrant validate`.
4. Run any existing automated tests or checks (if available).
5. Submit a pull request with a clear, concise description of the change.

See [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) for guidelines.

---

## License

All labs and documentation are provided under the MIT License. See [`../../LICENSE`](../../LICENSE) for details.

---

## Contact & Support

- **Issues:** Use GitHub Issues for bugs and feature requests.
- **Discussions:** Ask questions about setup, attacks, or improvements.
- **Pull Requests:** Contributions are welcome (documentation, code, and new scenarios).

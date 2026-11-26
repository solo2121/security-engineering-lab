# Detection and Blue Team Guide

A defensive counterpart to the lab attack guides. For every technique in the AD Pentest Lab and VLAN Lab, this guide shows what evidence it leaves behind, which event IDs to monitor, and how to write detection rules against it.

All Event IDs reference Windows Security, System, and Sysmon logs. Log sources assume Sysmon is installed and Windows Event Forwarding is configured.

---

## Table of Contents

1. [Lab Monitoring Setup](#1-lab-monitoring-setup)
2. [Sysmon Deployment](#2-sysmon-deployment)
3. [Reconnaissance Detection](#3-reconnaissance-detection)
4. [Credential Attack Detection](#4-credential-attack-detection)
5. [Active Directory Certificate Services Detection](#5-active-directory-certificate-services-detection)
6. [Modern AD Attack Detection](#6-modern-ad-attack-detection)
7. [Lateral Movement Detection](#7-lateral-movement-detection)
8. [Domain Compromise Detection](#8-domain-compromise-detection)
9. [Persistence Detection](#9-persistence-detection)
10. [Defense Evasion Detection](#10-defense-evasion-detection)
11. [Cloud and LLM Attack Detection](#11-cloud-and-llm-attack-detection)
12. [Falco Rules for the DevOps Lab](#12-falco-rules-for-the-devops-lab)
13. [Detection Rule Templates](#13-detection-rule-templates)
14. [Blue Team Checklist](#14-blue-team-checklist)

---

## 1. Lab Monitoring Setup

### Enable Key Windows Audit Policies

Run on the Domain Controller and all Windows hosts via Group Policy or directly:

```powershell
# Enable advanced audit policies
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
auditpol /set /subcategory:"Privilege Use" /success:enable /failure:enable
auditpol /set /subcategory:"Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable

# Enable PowerShell script block logging
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
  -Name "EnableScriptBlockLogging" -Value 1

# Enable PowerShell module logging
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" `
  -Name "EnableModuleLogging" -Value 1
```

### Windows Event Forwarding (WEF)

Collect logs from all Windows hosts to a central collector:

```powershell
# On each source host — enable WinRM
winrm quickconfig -q

# On the collector host — create a subscription
wecutil cs /c:subscription.xml

# Verify events are flowing
Get-WinEvent -LogName "ForwardedEvents" -MaxEvents 10
```

### Event Log Sizes

Increase log sizes to retain evidence longer:

```powershell
# Security log — set to 1 GB
wevtutil sl Security /ms:1073741824

# Sysmon log — set to 512 MB
wevtutil sl Microsoft-Windows-Sysmon/Operational /ms:536870912
```

---

## 2. Sysmon Deployment

Sysmon dramatically improves visibility into process creation, network connections, file writes, and registry changes.

### Install Sysmon

```powershell
# Download from Sysinternals
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "Sysmon.zip"
Expand-Archive Sysmon.zip

# Install with a hardened config (SwiftOnSecurity is widely used)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" `
  -OutFile "sysmonconfig.xml"

.\Sysmon64.exe -accepteula -i sysmonconfig.xml

# Verify running
Get-Service Sysmon64
```

### Key Sysmon Event IDs

| Event ID | Description | Why it matters |
|---|---|---|
| 1 | Process Create | Captures every process with full command line and parent |
| 3 | Network Connection | Outbound and inbound TCP/UDP connections |
| 5 | Process Terminated | Tracks short-lived processes |
| 7 | Image Loaded | DLL loads — catches DLL injection and hijacking |
| 8 | CreateRemoteThread | Cross-process thread injection |
| 10 | ProcessAccess | LSASS access for credential dumping |
| 11 | FileCreate | File written to disk |
| 12 | Registry Object Added/Deleted | Registry persistence |
| 13 | Registry Value Set | Registry value modification |
| 15 | FileCreateStreamHash | Alternate data stream creation |
| 17 | Pipe Created | Named pipe creation |
| 18 | Pipe Connected | Named pipe connection (getsystem) |
| 22 | DNS Query | DNS resolution — detects C2 beaconing |
| 25 | Process Tampering | Process hollowing detection |

---

## 3. Reconnaissance Detection

### Nmap Port Scanning

**What it leaves:**
- Rapid connection attempts to many ports from one source IP
- TCP SYN packets without completing handshake (SYN scan)
- Failed connection attempts across many ports

**Event IDs:** Windows Firewall logs (5156, 5157), Sysmon Event 3

**Detection rule:**

```
Alert if: single source IP makes >50 connection attempts in 60 seconds
  to destination ports spanning more than 20 unique values
```

**Lab action:** On the DC or WIN10, open Event Viewer → Windows Logs → Security → filter on Event ID 5156/5157 after running an nmap scan from Kali.

### BloodHound / LDAP Enumeration

**What it leaves:**
- High-volume LDAP queries in a short timeframe
- Queries for all users, groups, computers, and ACLs simultaneously
- Source is an authenticated domain user, not a service account

**Event IDs:** 4662 (Directory Service Access), 1644 (LDAP diagnostic — requires enablement)

**Enable LDAP diagnostic logging:**

```powershell
# On DC — enable LDAP interface events
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Diagnostics" `
  -Name "15 Field Engineering" -Value 5
```

**Detection:**

```
Alert if: single account issues >500 LDAP queries in 5 minutes
  AND queries include objectClass=user AND objectClass=group AND objectClass=computer
```

### DNS Zone Transfer

**What it leaves:** A single DNS query of type AXFR to port 53 TCP

**Event IDs:** DNS Server debug log (requires enablement)

```powershell
# Enable DNS debug logging on DC
Set-DnsServerDiagnostics -All $true
```

**Detection:** Alert on any AXFR query from a non-DC source IP.

---

## 4. Credential Attack Detection

### LLMNR / NBT-NS Poisoning (Responder)

**What it leaves:**
- Unusual NTLM authentication to an IP that is not a domain controller or known server
- LLMNR and NBT-NS broadcast traffic on the subnet
- NTLMv2 authentication events from hosts that were not trying to reach any known resource

**Event IDs:** 4624 (Logon), 4625 (Failed Logon)

**Detection:**

```
Alert if: NTLM authentication (Event 4624, Logon Type 3)
  where Workstation_Name does not match any known server hostname
  AND Authentication_Package = NTLM
```

**Mitigation:** Disable LLMNR via Group Policy:
```
Computer Configuration → Administrative Templates → Network →
DNS Client → Turn off multicast name resolution → Enabled
```

Disable NBT-NS:
```powershell
# Disable on all adapters
$adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true"
foreach ($adapter in $adapters) { $adapter.SetTcpipNetbios(2) }
```

### AS-REP Roasting

**What it leaves:** Kerberos AS-REQ without pre-authentication (PA-DATA missing)

**Event IDs:** 4768 (Kerberos TGT Request)

**Detection:**

```
Alert if: Event 4768
  where Pre_Authentication_Type = 0 (no pre-auth)
  AND Account_Name does not match known service accounts
```

**Lab exercise:**

```powershell
# On DC — find accounts with pre-auth disabled
Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth
```

### Kerberoasting

**What it leaves:** TGS request for a user account SPN with RC4 encryption

**Event IDs:** 4769 (Kerberos Service Ticket Request)

**Detection:**

```
Alert if: Event 4769
  where Ticket_Encryption_Type = 0x17 (RC4-HMAC)
  AND Account_Name does not end with $  (not a machine account)
  AND Service_Name does not equal krbtgt
```

**Lab exercise — watch for Kerberoasting:**

```powershell
# On DC — monitor for RC4 TGS requests in real time
Get-WinEvent -LogName Security -FilterXPath `
  "*[System[EventID=4769] and EventData[Data[@Name='TicketEncryptionType']='0x17']]" `
  -MaxEvents 20
```

### Password Spraying

**What it leaves:**
- Multiple failed logon attempts (4625) across many different accounts from one source
- Low failure count per account (avoids lockout) but high total count from same IP

**Event IDs:** 4625 (Failed Logon), 4771 (Kerberos Pre-Authentication Failed)

**Detection:**

```
Alert if: single source IP generates >10 Event 4625 failures
  across >5 unique Account_Name values
  in a 5-minute window
```

### NTLM Relay Attack

**What it leaves:**
- Successful authentication from one host to another using credentials that originated from a third host
- NTLM authentication followed immediately by SMB access on a different target
- Inbound SMB connection from an unexpected source

**Event IDs:** 4624 (Logon Type 3), 4648 (Explicit Credentials Logon)

**Detection:**

```
Alert if: Event 4624 Logon_Type=3
  where source IP is not the account's normal workstation
  AND authentication follows within 5 seconds of an outbound connection from source
```

**Mitigation:** Enable SMB signing on all hosts:

```powershell
# Via Group Policy (preferred) or directly:
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
  -Name "RequireSecuritySignature" -Value 1
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
  -Name "RequireSecuritySignature" -Value 1
```

### GPP Credential Extraction

**What it leaves:**
- SMB access to the SYSVOL share
- Reads of Groups.xml or other Preferences XML files

**Event IDs:** 5140 (Network Share Access), 4663 (File Access)

**Detection:**

```
Alert if: Event 5140
  where Share_Name = SYSVOL
  AND Source_Address is not a domain controller IP
  followed by: Event 4663 for access to any *.xml file under Policies\
```

**Mitigation:** Microsoft released MS14-025 which removes the ability to set passwords via GPP. Ensure all DCs are patched and audit SYSVOL for any remaining Groups.xml files containing `cpassword`:

```powershell
Get-ChildItem -Path "\\$env:USERDNSDOMAIN\SYSVOL" -Recurse -Include "*.xml" |
  Select-String -Pattern "cpassword" |
  Select-Object Path, Line
```

---

## 5. Active Directory Certificate Services Detection

### ESC1 — Enrollee Supplies Subject

**What it leaves:**
- Certificate enrollment where Subject Alternative Name differs from the enrolling account
- Certipy generates a specific RPC call pattern

**Event IDs:** 4886 (Certificate Request), 4887 (Certificate Issued)

**Enable AD CS auditing:**

```powershell
# On CA server
certutil -setreg CA\AuditFilter 127
net stop certsvc && net start certsvc
```

**Detection:**

```
Alert if: Event 4887
  where Requester is not a privileged account
  AND Certificate_Template has Client_Authentication EKU
  AND Certificate contains SAN for administrator or krbtgt
```

### ESC8 — NTLM Relay to HTTP Enrollment

**What it leaves:**
- HTTP requests to `/certsrv/` from an IP that is not the DC or CA
- NTLM authentication on port 80/443 on the CA server from an unexpected source

**Detection:**

```
Alert if: IIS access log on CA shows POST to /certsrv/certfnsh.asp
  where source IP is not in list of known admin workstations
  AND User-Agent is not a known browser
```

**Mitigation:** Enable EPA (Extended Protection for Authentication) on IIS Certificate Enrollment web services.

### ESC9 — No Security Extension

**Detection:**
```
Alert if: Event 4887
  where Certificate does not contain szOID_NTDS_CA_SECURITY_EXT
  AND Certificate has Client Authentication or Smart Card Logon EKU
  AND certificate was issued to a non-privileged account
```

---

## 6. Modern AD Attack Detection

### ZeroLogon — CVE-2020-1472

**What it leaves:**
- Rapid repeated Netlogon authentication attempts with zero-filled authenticator
- Machine account password reset to empty
- Event showing DC account password change not from a DC

**Event IDs:** 4742 (Computer Account Changed), 4625 (Failed Logon — many in rapid succession)

**Detection:**

```
Alert if: Event 4742
  where the Changed_Attributes includes Password_Last_Set
  AND the account being changed is a Domain Controller machine account ($)
  AND the source is not a known DC management tool

Alert if: >100 Netlogon authentication failures for a single machine account
  in under 10 seconds (the brute-force phase of ZeroLogon)
```

**Mitigation:** Apply MS-NRPC patches (August 2020 and February 2021 enforcement updates). Verify enforcement mode is active:

```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
  -Name "FullSecureChannelProtection"
# Expected: 1 (enforcement mode)
```

### PetitPotam — CVE-2021-36942

**What it leaves:**
- Outbound NTLM authentication from a DC to an unexpected destination
- MS-EFSRPC EfsRpcOpenFileRaw RPC call from an untrusted source

**Event IDs:** 4624 (Logon Type 3 from DC to external IP), Sysmon Event 3 (outbound network from lsass.exe)

**Detection:**

```
Alert if: Sysmon Event 3
  where Image = C:\Windows\System32\lsass.exe
  AND DestinationIp is not in list of known DCs or admin systems
  AND DestinationPort = 445
```

**Mitigation:** Apply KB5005413. Disable EFSRPC where not needed via firewall rules blocking port 445 inbound to DCs from non-DC sources.

### NoPac — CVE-2021-42287

**What it leaves:**
- Machine account created and immediately renamed to match DC name
- TGT requested for DC name without `$` suffix from a low-privilege account
- Kerberos S4U2Self abuse

**Event IDs:** 4741 (Computer Account Created), 4743 (Computer Account Changed — rename), 4768 (TGT Request with unusual name)

**Detection:**

```
Alert if: Event 4741 (machine account created)
  followed within 60 seconds by Event 4743 (same account renamed)
  where new name matches an existing DC name without trailing $

Alert if: Event 4768
  where Account_Name matches a DC hostname without $
  AND the requesting IP is not a DC
```

### Shadow Credentials

**What it leaves:**
- Write to `msDS-KeyCredentialLink` attribute on a computer or user object
- PKINIT Kerberos authentication immediately after the write

**Event IDs:** 4662 (Directory Service Access with write to msDS-KeyCredentialLink)

**Detection:**

```
Alert if: Event 4662
  where Object_Type = computer OR user
  AND Access_Mask includes WriteProperty
  AND Property_GUIDs includes the msDS-KeyCredentialLink attribute GUID
    (5b47d60f-6090-40b2-9f37-2a4de88f3063)
  AND the source account is not a known admin
```

### RBCD — Resource-Based Constrained Delegation

**What it leaves:**
- Write to `msDS-AllowedToActOnBehalfOfOtherIdentity` on a computer object
- S4U2Proxy ticket request immediately after

**Event IDs:** 4662 (write to msDS-AllowedToActOnBehalfOfOtherIdentity)

**Detection:**

```
Alert if: Event 4662
  where Property_GUIDs includes msDS-AllowedToActOnBehalfOfOtherIdentity
    (3f78c3e5-f79a-46bd-a0b8-9d18116ddc79)
  AND source account is not a known privileged admin
```

### PrintNightmare — CVE-2021-1675

**What it leaves:**
- Remote call to RpcAddPrinterDriverEx with a network UNC path for the DLL
- spoolsv.exe spawning a child process with SYSTEM privileges
- DLL loaded from a network path by spoolsv.exe

**Event IDs:** Sysmon Event 1 (spoolsv.exe child process), Sysmon Event 7 (DLL loaded from UNC path)

**Detection:**

```
Alert if: Sysmon Event 1
  where ParentImage = C:\Windows\System32\spoolsv.exe
  AND Image is not a known print driver binary

Alert if: Sysmon Event 7
  where Image = C:\Windows\System32\spoolsv.exe
  AND ImageLoaded starts with \\ (UNC path)
```

---

## 7. Lateral Movement Detection

### Pass-the-Hash

**What it leaves:**
- NTLM Type 3 authentication (logon type 9 — NewCredentials) from a workstation
- Successful authentication to a remote host with no corresponding interactive logon

**Event IDs:** 4624 (Logon Type 9), 4648 (Explicit Credentials Used)

**Detection:**

```
Alert if: Event 4624
  where Logon_Type = 9
  AND Authentication_Package = NTLM
  AND Workstation_Name != subject account's normal workstation
```

### PsExec / Remote Service Creation

**What it leaves:**
- Service created on the target with a random name
- SMB connection followed immediately by service installation
- PSEXESVC.exe or similar executable created in C:\Windows\

**Event IDs:** 4697 (Service Installed), 7045 (New Service Installed — System log), Sysmon Event 11 (file created in Windows directory)

**Detection:**

```
Alert if: Event 7045
  where Service_File_Name contains PSEXESVC
  OR Service_File_Name starts with C:\Windows\ and has a random-looking name (8 chars, no vowels)
  AND installation is not from a known management tool
```

### WMI Remote Execution

**What it leaves:**
- WMI Provider Host (WmiPrvSE.exe) spawning a child process
- Network logon to WMI port (135/TCP) from an external source

**Event IDs:** 4624 (Logon Type 3), Sysmon Event 1 (WmiPrvSE.exe child)

**Detection:**

```
Alert if: Sysmon Event 1
  where ParentImage = C:\Windows\System32\wbem\WmiPrvSE.exe
  AND Image is not a known WMI provider binary
  AND CommandLine contains suspicious keywords (cmd, powershell, net, wscript)
```

### Evil-WinRM / WinRM Remote Shell

**What it leaves:**
- Inbound connection on port 5985 (HTTP) or 5986 (HTTPS)
- wsmprovhost.exe spawning a child process

**Event IDs:** 4624 (Logon Type 3), Sysmon Event 1 (wsmprovhost.exe child)

**Detection:**

```
Alert if: Sysmon Event 1
  where ParentImage = C:\Windows\System32\wsmprovhost.exe
  AND Image is cmd.exe OR powershell.exe
```

---

## 8. Domain Compromise Detection

### DCSync

**What it leaves:**
- DS-Replication-Get-Changes-All access right exercised by a non-DC account
- Event 4662 with specific access mask and properties

**Event IDs:** 4662 (Directory Service Access)

**Detection — most important rule in AD security:**

```
Alert if: Event 4662
  where Subject_Account is not a Domain Controller machine account ($)
  AND Access_Mask = 0x100
  AND Properties contains {1131f6ad-9c07-11d1-f79f-00c04fc2dcd2}
    (DS-Replication-Get-Changes-All)
```

**Lab exercise — trigger DCSync and observe the event:**

```powershell
# On DC — watch for DCSync in real time
Get-WinEvent -LogName Security -FilterXPath `
  "*[System[EventID=4662] and EventData[Data[@Name='Properties'] and (Data='1131f6aa-9c07-11d1-f79f-00c04fc2dcd2' or Data='1131f6ad-9c07-11d1-f79f-00c04fc2dcd2')]]" `
  -MaxEvents 5
```

### Golden Ticket Usage

**What it leaves:**
- TGS requests using a TGT that was not issued by the DC (no corresponding 4768)
- TGT with an abnormally long lifetime (10 years by default with Mimikatz)
- Encryption type mismatch (RC4 TGT when AES is enforced)

**Event IDs:** 4769 (Service Ticket Request with no matching 4768)

**Detection:**

```
Alert if: Event 4769
  where no corresponding Event 4768 exists for the same account
  in the preceding 10-hour window

Alert if: Event 4769
  where Ticket_Encryption_Type = 0x17 (RC4)
  AND domain policy requires AES (0x12/0x11)
```

**Mitigation:** Rotate the krbtgt password twice (required because of the previous password rollover window). This invalidates all existing Golden Tickets.

```powershell
# Reset krbtgt — do this twice with a replication delay between
Set-ADAccountPassword -Identity krbtgt -Reset -NewPassword (ConvertTo-SecureString "NewPassword" -AsPlainText -Force)
```

### Silver Ticket Usage

**What it leaves:**
- TGS usage with no preceding TGT request (4769 without 4768)
- Service ticket issued for a service on a host that never requested it from the DC

**Detection:**

```
Alert if: Event 4769 (Service Ticket)
  where there is no preceding Event 4768 (TGT Request)
  from the same source IP in the preceding 8 hours
```

### Credential Dumping (LSASS)

**What it leaves:**
- Non-system process opening LSASS with PROCESS_VM_READ access
- Sysmon Event 10 with TargetImage = lsass.exe

**Event IDs:** Sysmon Event 10 (ProcessAccess)

**Detection:**

```
Alert if: Sysmon Event 10
  where TargetImage = C:\Windows\System32\lsass.exe
  AND SourceImage is not:
    C:\Windows\System32\werfault.exe
    C:\Windows\System32\svchost.exe
    C:\Program Files\*\antivirus.exe  (your AV)
  AND GrantedAccess includes 0x10 OR 0x20 OR 0x40
    (PROCESS_VM_READ, PROCESS_VM_WRITE, PROCESS_DUP_HANDLE)
```

---

## 9. Persistence Detection

### Scheduled Task Creation

**Event IDs:** 4698 (Scheduled Task Created), 4699 (Scheduled Task Deleted), Sysmon Event 1

**Detection:**

```
Alert if: Event 4698
  where Task_Content contains:
    powershell -enc  (base64 encoded command)
    cmd /c
    wscript.exe
    mshta.exe
    regsvr32.exe
    rundll32.exe
  AND Subject_Account is not a known admin or management tool
```

### Registry Run Key Persistence

**Event IDs:** Sysmon Event 13 (Registry Value Set)

**Detection:**

```
Alert if: Sysmon Event 13
  where TargetObject contains:
    \Software\Microsoft\Windows\CurrentVersion\Run
    \Software\Microsoft\Windows\CurrentVersion\RunOnce
    \SYSTEM\CurrentControlSet\Services\
  AND Details is a path to an executable not in a known-good location
```

### New Service Installation

**Event IDs:** 4697 (Service Installed), 7045 (System log)

**Detection:**

```
Alert if: Event 7045
  where Service_Start_Type = Auto
  AND Service_File_Name is not in a known-good path
  AND installation is not from a software deployment tool
```

### Backdoor User Account

**Event IDs:** 4720 (User Account Created), 4732 (Member Added to Group)

**Detection:**

```
Alert if: Event 4720 (user created)
  where Subject_Account is not a known provisioning account
  AND creation time is outside business hours

Alert if: Event 4732
  where Group_Name = "Domain Admins" OR "Administrators" OR "Enterprise Admins"
  AND Subject_Account is not a known admin provisioning account
```

### ACL Backdoor

**Event IDs:** 4662 (Directory Service Access — write)

**Detection:**

```
Alert if: Event 4662
  where Access_Mask includes WriteProperty OR WriteDACL
  AND Object_DN is a high-value target (Domain Admins, AdminSDHolder, Domain root)
  AND Subject_Account is not a known privileged admin
```

---

## 10. Defense Evasion Detection

### Event Log Clearing

**Event IDs:** 1102 (Security log cleared), 104 (System log cleared — System log)

**Detection:**

```
Alert if: Event 1102 OR Event 104
  — any occurrence is suspicious
  — this should never happen in normal operations
```

### AMSI Bypass

**What it leaves:**
- PowerShell script block logging captures the bypass attempt itself
- Sysmon Event 1 shows PowerShell with -EncodedCommand or -NoProfile flags

**Event IDs:** 4104 (PowerShell Script Block Logging)

**Detection:**

```
Alert if: Event 4104
  where ScriptBlock contains:
    "AmsiUtils"
    "amsiInitFailed"
    "amsiContext"
    "AmsiScanBuffer"
    "[Runtime.InteropServices.Marshal]::Copy"
```

### Process Hollowing / Injection

**Event IDs:** Sysmon Event 8 (CreateRemoteThread), Sysmon Event 25 (Process Tampering)

**Detection:**

```
Alert if: Sysmon Event 8
  where TargetImage is a legitimate Windows process (explorer.exe, svchost.exe)
  AND SourceImage is NOT a known system component

Alert if: Sysmon Event 25
  — any occurrence is suspicious
```

### Living Off the Land (LOLBins)

Attackers use legitimate Windows binaries to avoid AV detection.

**Detection — monitor these binaries when used unexpectedly:**

```
Sysmon Event 1 where Image contains any of:
  mshta.exe        (HTML Application host)
  regsvr32.exe     (COM register — used for script execution)
  rundll32.exe     (DLL runner — used for shellcode)
  certutil.exe     (Certificate tool — used to download files)
  bitsadmin.exe    (Background transfer — used to download files)
  wscript.exe      (Windows Script Host)
  cscript.exe      (Windows Script Host CLI)
  installutil.exe  (AppLocker bypass)

Alert if any of the above:
  - has a network connection (Sysmon Event 3) immediately after execution
  - loads a DLL from a temp or user-writable path (Sysmon Event 7)
  - spawns cmd.exe or powershell.exe as a child (Sysmon Event 1)
```

---

## 11. Cloud and LLM Attack Detection

### LocalStack S3 Access (cloud-pentest VM)

Monitor access to the cloud simulation VM for unauthorized enumeration.

**On the cloud-pentest VM — enable access logging:**

```bash
# Enable LocalStack request logging
export LS_LOG=debug
localstack start

# Watch for bucket enumeration
tail -f /var/log/localstack.log | grep -E "ListBuckets|GetObject|ListObjects"

# Alert on any access to internal-docs bucket from unexpected source
tail -f /var/log/localstack.log | grep "internal-docs" | grep -v "10.0.0.1"
```

**Detection patterns:**

```
Alert if: LocalStack log shows ListBuckets or ListUsers
  where source IP is not in authorized IP list

Alert if: LocalStack log shows GetObject on internal-docs or backup-data buckets
  where source IP is Kali (172.28.x.10)
```

### EC2 Metadata Service Abuse

```bash
# Monitor metadata service access
tail -f /var/log/nginx/access.log | grep "latest/meta-data/iam"

# Alert on credential endpoint access
grep "security-credentials" /var/log/nginx/access.log | tail -20
```

**Detection:**

```
Alert if: metadata service access log shows request to:
  /latest/meta-data/iam/security-credentials/
  where source IP is not the application server IP
```

### LLM Endpoint Abuse (llm01 VM)

The app logs structured JSON to stdout. On `llm01` it runs in Docker, so the logs come
from the container (if provisioning fell back to the Python service, use
`journalctl -u llm-owasp-lab` instead). See
[`llm-lab/README.md`](../../../labs/security/active-directory/base/llm-lab/README.md).

```bash
# On llm01 — follow all lab-app log output
sudo docker compose -f /opt/llm-lab/docker-compose.yml --profile lab logs -f llm-lab-vulnerable

# Alert on suspicious prompt content or blocked actions
sudo docker compose -f /opt/llm-lab/docker-compose.yml --profile lab logs -f llm-lab-vulnerable | grep -iE \
  "override_detected.:true|blocked_command|blocked_path_traversal|rate_limited|daily_quota_exceeded"
```

**Detection patterns:**

```
Alert if: the llm-lab container log shows:
  "override_detected":true          (LLM01 prompt-injection attempt against /llm01/chat)
  "blocked_command"                 (LLM06 attempted a non-allowlisted "tool" command)
  "blocked_path_traversal"          (LLM06/LLM02 attempted to escape the data/sandbox path)
  "cross_tenant_leak":true          (LLM08 rag-query returned another tenant's documents)
  "rate_limited" or "daily_quota_exceeded" repeated from the same client_id (LLM10 abuse)
```

---

## 12. Falco Rules for the DevOps Lab

These rules detect suspicious activity in your k3s cluster (DevOps lab). Deploy on the `devops-1` VM.

### Container Escape Attempts

```yaml
# /etc/falco/rules.d/lab-rules.yaml

- rule: Container running as root attempts shell
  desc: A container running as root spawned a shell
  condition: >
    spawned_process and
    container and
    proc.name in (shell_binaries) and
    user.uid = 0
  output: >
    Root shell spawned in container
    (user=%user.name container=%container.name image=%container.image.repository
    cmd=%proc.cmdline)
  priority: WARNING

- rule: Sensitive file access in container
  desc: Sensitive file read inside a container
  condition: >
    open_read and
    container and
    fd.name in (/etc/shadow, /etc/passwd, /root/.ssh/authorized_keys, /var/run/secrets/kubernetes.io/serviceaccount/token)
  output: >
    Sensitive file read in container
    (file=%fd.name container=%container.name image=%container.image.repository
    user=%user.name)
  priority: HIGH
```

### Kubernetes API Abuse

```yaml
- rule: Suspicious kubectl exec
  desc: kubectl exec into a production-like namespace
  condition: >
    ka.verb = "create" and
    ka.target.subresource = "exec" and
    not ka.user.name in (known-admin-users)
  output: >
    kubectl exec by unexpected user
    (user=%ka.user.name pod=%ka.target.name ns=%ka.target.namespace)
  priority: WARNING

- rule: ClusterRole with wildcard permissions created
  desc: A ClusterRole with * permissions was created
  condition: >
    ka.verb in (create, update) and
    ka.target.resource = "clusterroles" and
    ka.request.object contains '"*"'
  output: >
    Overly permissive ClusterRole created
    (user=%ka.user.name role=%ka.target.name)
  priority: HIGH

- rule: ServiceAccount token mounted in suspicious pod
  desc: Pod created with automounted service account token in unexpected namespace
  condition: >
    ka.verb = "create" and
    ka.target.resource = "pods" and
    ka.target.namespace != "kube-system" and
    ka.request.object contains '"automountServiceAccountToken":true'
  output: >
    Pod with service account token in non-system namespace
    (user=%ka.user.name pod=%ka.target.name ns=%ka.target.namespace)
  priority: WARNING
```

### Harbor Registry Abuse

```yaml
- rule: Unexpected image push to Harbor
  desc: Image pushed to Harbor from unexpected source
  condition: >
    ka.verb = "create" and
    ka.target.resource = "artifacts" and
    not ka.user.name in (known-ci-users)
  output: >
    Unexpected image push to Harbor
    (user=%ka.user.name project=%ka.target.namespace image=%ka.target.name)
  priority: WARNING
```

### Reload Falco after adding rules

```bash
vagrant ssh devops-1
sudo systemctl reload falco

# Verify rules loaded
sudo falco --list | grep "lab-rules"

# Watch Falco alerts in real time
sudo journalctl -fu falco
```

---

## 13. Detection Rule Templates

Use these as starting points for your SIEM or log aggregation stack.

### Sigma Rule — DCSync

```yaml
title: DCSync Attack Detected
status: stable
description: Detects replication of domain credentials by a non-DC account
logsource:
  product: windows
  service: security
detection:
  selection:
    EventID: 4662
    Properties|contains:
      - '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'
      - '1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'
  filter:
    SubjectUserName|endswith: '$'
  condition: selection and not filter
falsepositives:
  - Azure AD Connect
  - Known replication tools
level: critical
tags:
  - attack.credential_access
  - attack.t1003.006
```

### Sigma Rule — Kerberoasting

```yaml
title: Kerberoasting Activity
status: stable
description: Detects RC4 TGS requests indicative of Kerberoasting
logsource:
  product: windows
  service: security
detection:
  selection:
    EventID: 4769
    TicketEncryptionType: '0x17'
  filter:
    ServiceName|endswith: '$'
  condition: selection and not filter
falsepositives:
  - Legacy applications that require RC4
level: high
tags:
  - attack.credential_access
  - attack.t1558.003
```

### Sigma Rule — LSASS Access

```yaml
title: LSASS Memory Access
status: stable
description: Detects processes accessing LSASS memory for credential dumping
logsource:
  product: windows
  service: sysmon
detection:
  selection:
    EventID: 10
    TargetImage|endswith: '\lsass.exe'
    GrantedAccess|contains:
      - '0x1010'
      - '0x1410'
      - '0x147a'
      - '0x143a'
  filter:
    SourceImage|startswith:
      - 'C:\Windows\System32\'
      - 'C:\Windows\SysWOW64\'
      - 'C:\Program Files\'
  condition: selection and not filter
falsepositives:
  - AV/EDR solutions
level: high
tags:
  - attack.credential_access
  - attack.t1003.001
```

---

## 14. Blue Team Checklist

Use this after running attack scenarios in the lab to verify detection coverage.

### After LLMNR/Responder

- [ ] Event 4624 Logon Type 3 visible from unexpected source
- [ ] NTLM authentication to non-DC IP visible
- [ ] Responder logs show captured hashes

### After AS-REP / Kerberoasting

- [ ] Event 4768 with Pre_Auth_Type=0 visible for AS-REP
- [ ] Event 4769 with TicketEncryptionType=0x17 visible for Kerberoasting
- [ ] Alerts fired if rules are configured

### After BloodHound Collection

- [ ] High LDAP query volume visible in DC logs
- [ ] Event 1644 visible (if LDAP diagnostics enabled)

### After DCSync

- [ ] Event 4662 with DS-Replication properties visible
- [ ] Source account is NOT a machine account ($)
- [ ] Alert fired

### After Credential Dumping

- [ ] Sysmon Event 10 visible with LSASS as target
- [ ] Source process is not a known system component
- [ ] Alert fired

### After Scheduled Task Persistence

- [ ] Event 4698 visible with suspicious task content
- [ ] Alert fired

### After Log Clearing

- [ ] Event 1102 visible
- [ ] Alert fired immediately

### Ongoing Hardening Verification

- [ ] SMB signing enabled on all hosts (`nmap --script smb2-security-mode`)
- [ ] LLMNR disabled via GPO
- [ ] NBT-NS disabled on all adapters
- [ ] Kerberos AES enforced (RC4 disabled)
- [ ] LAPS deployed on all workstations
- [ ] krbtgt password rotated in last 30 days
- [ ] WEF configured and events flowing to collector
- [ ] Sysmon running on all Windows hosts
- [ ] Falco running in DevOps lab

---

## Disclaimer

This guide is for authorized security research and detection engineering in the isolated lab environment. Apply these detections in authorized environments only.

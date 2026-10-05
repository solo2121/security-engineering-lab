# Windows Server Hardening Guide

This is the control-by-control reference for what `dc01-hardened`'s
`phase4-hardening-baseline` provisioner applies, why each control matters,
what it costs you (if anything), and how to test that it's actually
working — including, where practical, by reusing the AD pentest lab's own
attack tooling against this lab.

Each section is written the same way: **Control → Why → Attack it
mitigates → How to verify → Cost/trade-off.**

---

## Table of Contents

1. [LLMNR and NetBIOS-NS disabled](#1-llmnr-and-netbios-ns-disabled)
2. [SMB signing required](#2-smb-signing-required)
3. [NTLM restriction (audit-only baseline)](#3-ntlm-restriction-audit-only-baseline)
4. [NTLMv1/LM refused](#4-ntlmv1lm-refused)
5. [Print Spooler disabled](#5-print-spooler-disabled)
6. [SMBv1 disabled](#6-smbv1-disabled)
7. [Windows Defender real-time protection enabled](#7-windows-defender-real-time-protection-enabled)
8. [Audit policy hardened](#8-audit-policy-hardened)
9. [Domain password policy hardened](#9-domain-password-policy-hardened)
10. [What this baseline does not yet cover](#10-what-this-baseline-does-not-yet-cover)
11. [Testing against the AD pentest lab's own tooling](#11-testing-against-the-ad-pentest-labs-own-tooling)

---

## 1. LLMNR and NetBIOS-NS disabled

**Control:** `EnableMulticast` set to `0` under the DNS Client group policy
key; NetBIOS over TCP/IP disabled on every adapter.

**Why:** LLMNR and NBT-NS are fallback name-resolution protocols that
respond to *any* broadcast query, including deliberately mistyped ones.
Tools like Responder exploit this to capture NTLM authentication attempts.

**Attack it mitigates:** LLMNR/NBT-NS poisoning — see
[`attack-guide.md` §4 Initial Access](../../active-directory/base/docs/attack-guide.md#4-initial-access)
in the AD pentest lab, where the flat network's DC and clients respond to
these broadcasts by design.

**How to verify:**
```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast
# Expect: EnableMulticast : 0
```

**Cost/trade-off:** None in a domain environment with working DNS — LLMNR
and NBT-NS exist as fallbacks for when DNS fails, and a healthy domain
shouldn't rely on them.

---

## 2. SMB signing required

**Control:** `RequireSecuritySignature` set to `$true` on both the SMB
server and client configuration.

**Why:** Without required signing, an attacker positioned to intercept
traffic can relay captured NTLM authentication to another SMB target
instead of just cracking it offline.

**Attack it mitigates:** NTLM relay — see
[`attack-guide.md` §5 Credential Attacks, "NTLM Relay Attack"](../../active-directory/base/docs/attack-guide.md#5-credential-attacks).

**How to verify:**
```powershell
Get-SmbServerConfiguration | Select RequireSecuritySignature
Get-SmbClientConfiguration | Select RequireSecuritySignature
# Expect: True for both
```

**Cost/trade-off:** Slight CPU overhead per SMB session (generally
negligible on modern hardware) and it will break any legacy client that
can't sign — verify compatibility before applying in a real environment.

---

## 3. NTLM restriction (audit-only baseline)

**Control:** `RestrictReceivingNTLMTraffic` set to `1` (audit) rather than
`2` (deny all), with `AuditReceivingNTLMTraffic` enabled.

**Why:** Fully denying NTLM is the stronger control, but it will break
anything in your environment still depending on NTLM (older applications,
some service accounts, certain third-party tools) with little warning.
This baseline ships in audit mode deliberately so you can review what NTLM
traffic actually occurs before committing to a hard deny.

**Attack it mitigates:** Reduces (in audit mode) or eliminates (once moved
to deny) NTLM-based relay and pass-the-hash paths generally.

**How to verify:**
```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name RestrictReceivingNTLMTraffic
# Expect: 1 (audit) in this baseline
```
NTLM audit events land in `Applications and Services Logs > Microsoft >
Windows > NTLM > Operational`.

**Moving to enforcement:** after reviewing the audit log for legitimate
NTLM dependencies, set `RestrictReceivingNTLMTraffic` to `2` and add any
required exceptions via
`HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0\ClientAllowedNTLMServers`
/ `DCAllowedNTLMServers`. This is a manual, environment-specific step —
not something this lab's provisioner does for you, since a wrong deny list
can lock out legitimate services.

---

## 4. NTLMv1/LM refused

**Control:** `LmCompatibilityLevel` set to `5` ("Send NTLMv2 response
only, refuse LM & NTLM").

**Why:** NTLMv1 and LM hashes are cryptographically weak enough to be
practically crackable; refusing them forces every authentication attempt
through the much stronger NTLMv2 exchange.

**Attack it mitigates:** NTLM downgrade attacks and offline cracking of
captured LM/NTLMv1 hashes — relevant to the same
[credential-attack section](../../active-directory/base/docs/attack-guide.md#5-credential-attacks)
as SMB relay above.

**How to verify:**
```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel
# Expect: 5
```

**Cost/trade-off:** None for any client from Windows 2000 SP4 onward —
this has been safe to enforce for a very long time.

---

## 5. Print Spooler disabled

**Control:** Spooler service stopped and startup type set to `Disabled`.

**Why:** The Print Spooler service was the vector for PrintNightmare, a
remote code execution and privilege escalation vulnerability affecting
domain controllers running the spooler unnecessarily.

**Attack it mitigates:** PrintNightmare (CVE-2021-1675 / CVE-2021-34527) —
see
[`attack-guide.md` §7 Modern AD Attacks](../../active-directory/base/docs/attack-guide.md#7-modern-ad-attacks)
and the matching
[`detection-and-blue-team.md` §6](../../../../docs/guides/security/detection-and-blue-team.md#6-modern-ad-attack-detection)
entry.

**How to verify:**
```powershell
Get-Service Spooler | Select Status, StartType
# Expect: Stopped, Disabled
```

**Cost/trade-off:** A domain controller has no business running a print
spooler in the first place — this is close to a free win. A dedicated
print server (like `print01` in the AD pentest lab) is a different case
and needs the spooler on, with other PrintNightmare mitigations applied
instead (patching, Point and Print restrictions).

---

## 6. SMBv1 disabled

**Control:** `SMB1Protocol` optional feature disabled.

**Why:** SMBv1 is a legacy protocol with a long history of severe
vulnerabilities (EternalBlue among them) and no modern reason to remain
enabled on a domain controller.

**Attack it mitigates:** Legacy SMB exploitation generally; not
specifically demonstrated in the current AD pentest lab attack guide, but
included here as a standard hardening baseline item.

**How to verify:**
```powershell
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol | Select State
# Expect: Disabled
```

**Cost/trade-off:** None for any modern client or application. Breaks
compatibility with very old (pre-Vista) SMB clients only.

---

## 7. Windows Defender real-time protection enabled

**Control:** `DisableRealtimeMonitoring` set to `$false` — i.e., Defender
is left **on**, which is the opposite of the AD pentest lab's baseline.

**Why:** The AD pentest lab intentionally disables Defender so its
training payloads and tooling aren't blocked mid-exercise. A hardened lab
should demonstrate the normal, secure default instead.

**Attack it mitigates:** General malware execution and some
post-exploitation tooling, though determined attackers routinely bypass
signature-based AV — this control is a baseline expectation, not a
complete defense.

**How to verify:**
```powershell
Get-MpComputerStatus | Select RealTimeProtectionEnabled
# Expect: True
```

**Cost/trade-off:** Real-time scanning has a measurable but generally
acceptable performance cost on a server workload.

---

## 8. Audit policy hardened

**Control:** `auditpol` enables success and failure auditing for Kerberos
Authentication Service, Kerberos Service Ticket Operations, Credential
Validation, Directory Service Access, Directory Service Changes, Security
Group Management, User Account Management, Logon, and Certification
Services. Security event log size is raised to 1 GB to reduce rollover.

**Why:** Every attack technique in the AD pentest lab's attack guide
generates specific, identifiable Windows events — but only if the relevant
audit subcategory is enabled and the log doesn't roll over before anyone
looks at it. This is the same audit-policy list documented in this repo's
[`detection-and-blue-team.md` §1 Lab Monitoring Setup](../../../../docs/guides/security/detection-and-blue-team.md#1-lab-monitoring-setup).

**Attack it mitigates:** Not an attack mitigation directly — a *detection
enablement* control. Without it, Kerberoasting (4769), AS-REP roasting
(4768), DCSync (4662), and AD CS abuse (4886/4887) are effectively
invisible regardless of what else you harden.

**How to verify:**
```powershell
auditpol /get /subcategory:"Kerberos Service Ticket Operations"
# Expect: Success and Failure both "Enable"
```

**Cost/trade-off:** Increased event log volume — budget log storage and,
ideally, forward events to a SIEM rather than relying on local retention
alone (see
[`detection-and-blue-team.md` §1, "Windows Event Forwarding"](../../../../docs/guides/security/detection-and-blue-team.md#1-lab-monitoring-setup)).

---

## 9. Domain password policy hardened

**Control:** 14-character minimum length, complexity enabled, 90-day max
age, 1-day min age, lockout after 5 failed attempts with a 15-minute
lockout and observation window.

**Why:** The AD pentest lab's default domain policy has complexity
disabled and a zero-length minimum specifically so its intentionally
weak service-account passwords (`svc_kerberoast`, `svc_asrep`, etc.) are
crackable within a training session. A hardened baseline should look like
what you'd actually deploy.

**Attack it mitigates:** Password spraying and brute-force —
[`attack-guide.md` §4 Initial Access, "Password Spraying"](../../active-directory/base/docs/attack-guide.md#4-initial-access).
Length and complexity also raise the cost of offline cracking for any
hash that is captured despite the other controls above.

**How to verify:**
```powershell
Get-ADDefaultDomainPasswordPolicy
# Expect: ComplexityEnabled True, MinPasswordLength 14, LockoutThreshold 5
```

**Cost/trade-off:** Standard password-policy trade-offs (user friction,
help-desk load for lockouts). A 15-minute lockout window is intentionally
short for a lab; production environments often tune this differently.

---

## 10. What this baseline does not yet cover

Being explicit about scope so this doesn't read as more comprehensive than
it is:

- **AD CS hardening** — the AD pentest lab's ESC1/4/7/8/9 templates
  (`ca01-esc`) aren't present in this lab at all yet (no CA is installed).
  If you extend this lab toward `LAB_PROFILE=full` parity with the AD
  pentest lab, template-permission hardening (removing low-priv enroll
  rights, requiring manager approval on sensitive templates) belongs here.
- **LAPS, Sysmon + WEF, and Credential Guard** — not part of the default
  baseline above, but available as opt-in controls (`HARDENING_ADVANCED=1`);
  see [`advanced-controls.md`](advanced-controls.md) for what each does, how
  to verify it, and its limits. They have not been validated end to end.
  Credential Guard needs UEFI, Secure Boot, and nested virtualization in the
  guest; it is skipped with an explicit reason when those are missing,
  instead of being reported as protection that isn't running. Manual Sysmon
  steps remain documented in
  [`detection-and-blue-team.md` §2](../../../../docs/guides/security/detection-and-blue-team.md#2-sysmon-deployment).
- **ZeroLogon / PetitPotam / NoPac / Shadow Credentials / RBCD
  mitigations** — these are largely patch-level and configuration-specific
  mitigations (Netlogon secure channel enforcement, EPA on AD CS web
  enrollment, etc.) not yet implemented in the automated baseline. See the
  matching
  [`detection-and-blue-team.md` §6](../../../../docs/guides/security/detection-and-blue-team.md#6-modern-ad-attack-detection)
  entries for what to watch for in the meantime.

## 11. Testing against the AD pentest lab's own tooling

Because both labs use the same base box and provisioning pattern, you can
validate several controls directly by pointing the AD pentest lab's Kali
attacker VM at `dc01-hardened` instead of `dc01` — **as long as both labs
are on isolated, non-overlapping networks and you understand you're now
running cross-lab traffic between two Vagrant environments.**

Examples (adjust IPs to your actual `VM_IPS` values):

```bash
# From the AD pentest lab's kali VM, or any attacker box with Responder installed:
# Should capture nothing meaningful once LLMNR/NetBIOS are disabled on dc01-hardened
sudo responder -I eth1

# NTLM relay attempt against dc01-hardened should fail once SMB signing is required
ntlmrelayx.py -tf targets.txt -smb2support
```

This is a manual exercise, not an automated cross-lab test — there is no
script in this repository that wires the two labs together yet (see
[`docs/project/roadmap.md`](../../../../docs/project/roadmap.md) "Create a
cross-lab scenario connecting the Active Directory pentest lab with the
DevOps lab's exposed services" for the closest existing roadmap item,
which does not currently cover this hardening lab).

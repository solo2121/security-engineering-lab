# Advanced Controls: LAPS, Sysmon + WEF, Credential Guard

This document covers the opt-in controls added after the `v0.1.0` MVP baseline.
They use the same format as the [hardening guide](hardening-guide.md):
**Control, Why, Attack it mitigates or detects, How to verify, Cost/trade-off.**

These controls are **off by default**. Nothing changes for an existing
`vagrant up` unless you export `HARDENING_ADVANCED=1`.

| Control | Type | Default when `HARDENING_ADVANCED=1` | Needs |
| --- | --- | --- | --- |
| Windows LAPS | Mitigation | On | A member server (the local-admin password of a DC is not what LAPS protects here) |
| Sysmon | Detection | On | Internet for the first install (Sysinternals), or a pre-seeded host |
| Windows Event Forwarding | Detection | On | A collector (the member server) and a source (every machine) |
| Credential Guard / VBS | Mitigation | **Off**; also needs `HARDENING_CREDENTIAL_GUARD=1` | Nested virtualization and UEFI/Secure Boot in the guest; member server only |

## Topology

```
dc01-hardened   domain controller        LAPS schema/OU/GPO, Sysmon, WEF source
srv01-hardened  member server (LabServers OU)
                                          LAPS client, WEF collector, Sysmon,
                                          Credential Guard (opt-in)
```

`srv01-hardened` is one extra VM. It plays three roles to keep the footprint
small. For a larger lab, split the collector onto its own VM and point
`LAB_COLLECTOR_FQDN` at it.

## Prerequisites

- The `vagrant-reload` plugin (reboots between steps).
- A Vagrant version that supports `env:` on the shell provisioner for Windows
  guests (2.3 or later is recommended).
- A Windows Server 2019/2022 box with the **April 2023 or later cumulative
  update** (needed for built-in Windows LAPS). The LAPS script stops with a
  clear message if the cmdlets are missing.

## Configuration (host environment)

Export these before `vagrant up`. Do not commit values; the domain admin
password in particular must only ever live in your shell.

| Variable | Required | Meaning |
| --- | --- | --- |
| `HARDENING_ADVANCED` | yes | `1` enables LAPS, Sysmon, and WEF |
| `HARDENING_CREDENTIAL_GUARD` | no | `1` also attempts Credential Guard on the member server |
| `LAB_DOMAIN` | yes | AD DNS name of the hardened lab domain |
| `LAB_DC_IP` | yes | IP of `dc01-hardened` on the lab network |
| `LAB_DOMAIN_ADMIN_PASSWORD` | yes | Password of the domain admin used to join and verify |
| `LAB_DOMAIN_ADMIN` | no | Defaults to `Administrator` |
| `LAB_SERVERS_OU` | no | Defaults to `LabServers` |
| `LAB_COLLECTOR_FQDN` | no | Defaults to `srv01-hardened.<LAB_DOMAIN>` |
| `SYSMON_CONFIG_SOURCE` | no | `swift` (default), `modular`, or `bundled` |
| `SYSMON_CONFIG_SHA256` | no | Pin the downloaded config; a mismatch is fatal |
| `HARDENING_STRICT` | no | `1` makes verification failures fail `vagrant up` |

## Wiring into the Vagrantfile

The helper lives in `provision/advanced/vagrant_advanced.rb`. Add it to the lab
`Vagrantfile`:

```ruby
require_relative "provision/advanced/vagrant_advanced"

# Inside the existing dc01-hardened definition, AFTER the existing provisioners
# (domain promotion and phase4-hardening-baseline must run first):
AdvancedControls.apply_dc(node)

# A new member server definition, using the same box and private network
# as dc01-hardened:
config.vm.define "srv01-hardened" do |node|
  node.vm.hostname = "srv01-hardened"
  # box, private-network IP, CPU/RAM (4 GB RAM recommended) as for dc01-hardened
  AdvancedControls.apply_member(node)
end
```

Bring the DC up first so the LabServers OU and the LAPS GPO exist before the
member server joins:

```bash
export HARDENING_ADVANCED=1 LAB_DOMAIN=... LAB_DC_IP=... LAB_DOMAIN_ADMIN_PASSWORD=...
vagrant up dc01-hardened
vagrant up srv01-hardened
```

---

## 1. Windows LAPS

**Control:** The DC extends the AD schema (`Update-LapsADSchema`), creates the
`LabServers` OU, grants computers in it permission to write their own password
(`Set-LapsADComputerSelfPermission`), and links a GPO that enables Windows LAPS
with AD backup, a 20-character complex password, and a 30-day rotation. The
member server joins into that OU. The built-in Administrator is managed; the
`vagrant` account is deliberately not, so rotation cannot lock Vagrant out.
If the domain functional level is 2016 or higher, AD password encryption is
enabled as well.

**Why:** A shared local administrator password means one compromised machine
gives an attacker administrative access to every machine that shares it. LAPS
makes each machine's local administrator password unique and rotating, stored
in AD with access controlled by ACLs.

**Attack it mitigates:** Lateral movement by reusing a local administrator
credential or hash across machines (pass-the-hash with a shared local admin).
Compare with the flat, shared-credential assumptions in the AD pentest lab's
[attack guide](../../active-directory/base/docs/attack-guide.md).

**How to verify:** The provisioner prints `PASS` when the escrow is confirmed.
Manually, from a domain-joined machine with the LAPS module and appropriate
rights:

```powershell
Get-LapsADPassword -Identity srv01-hardened -AsPlainText
# Expect: Account Administrator, a 20-character password, and a future ExpirationTimestamp
```

On the member server, `Get-WinEvent -LogName Microsoft-Windows-LAPS/Operational`
shows policy processing and the AD update.

**Cost/trade-off:** Domain admins can read these passwords by default; in a
real deployment, scope the read permission with `Set-LapsADReadPasswordPermission`.
LAPS here does not manage the DC's DSRM password (possible with Windows LAPS but
out of scope for this change).

## 2. Sysmon with a community baseline

**Control:** Sysmon64 is downloaded from Sysinternals, its Authenticode
signature is verified, and it is installed with the SwiftOnSecurity
`sysmon-config` by default (`modular` selects Olaf Hartong's `sysmon-modular`).
If the download fails or the installed Sysmon rejects the schema, a small
bundled baseline (`provision/advanced/config/sysmon-lab-baseline.xml`) is used
and a `WARN` is printed. The Sysmon log is sized to 256 MB.

**Why:** Hardening reduces what attackers can do; telemetry shows what they
tried. The audit policy in the base guide covers Windows security events, but
process creation chains, LSASS access, remote threads, and persistence
changes need Sysmon.

**Attack it detects:** Credential dumping from LSASS (Event 10), suspicious
process chains from Office or script hosts (Event 1), remote thread injection
(Event 8), persistence via Run keys and WMI (Events 12-14, 19-21), and remote
execution pipes (Events 17/18).

**How to verify:**

```powershell
Get-Service Sysmon64                      # Running
Get-Content C:\ProgramData\LabSysmon\state.json   # which config is active, and its SHA-256
Get-WinEvent -LogName Microsoft-Windows-Sysmon/Operational -MaxEvents 5
```

**Cost/trade-off:** Added log volume and a small CPU cost. The default config
download is unpinned unless you set `SYSMON_CONFIG_SHA256`; the script prints
the hash of what it fetched so you can pin it. Check the license and
attribution terms of any community config before redistributing it.

## 3. Windows Event Forwarding

**Control:** `srv01-hardened` enables the Windows Event Collector service and
registers a source-initiated subscription (`LabBaseline`, see
`provision/advanced/config/wef-subscription.xml`) that accepts Domain Computers.
Every machine sets the Subscription Manager policy to the collector, lets
`NETWORK SERVICE` read the Security and Sysmon logs through Event Log Readers,
and enables PowerShell script block logging. Forwarded: all Sysmon events,
selected Security events (4624/4625/4648/4662/4672/4697/4698/4720/4724/4728/
4732/4768/4769/4771/4776/4886/4887/5136), service installs (7045), PowerShell
4103/4104, and NTLM audit events. They land in `ForwardedEvents` on the
collector.

**Why:** Logs that stay on the machine an attacker controls can be cleared or
ignored. Central collection gives one place to look and survives local tampering.

**Attack it detects:** Kerberoasting (4769), AS-REP roasting (4768), DCSync
(4662), AD CS abuse (4886/4887), and the Sysmon-based detections above, all
visible from one machine. Pair with
[`detection-and-blue-team.md`](../../../../docs/guides/security/detection-and-blue-team.md).

**How to verify:** The provisioner polls and prints `PASS` once Sysmon events
from another machine arrive. Manually, on the collector:

```powershell
wecutil gr LabBaseline
Get-WinEvent -LogName ForwardedEvents -MaxEvents 20 | Group-Object MachineName
```

**Cost/trade-off:** Delivery uses HTTP (5985) with Kerberos message-level
protection, which is the standard WEF design but is not HTTPS. The Subscription
Manager value is set locally here for simplicity; in a larger lab deliver it
with a GPO. High-volume event IDs (4624, 4662) will grow `ForwardedEvents`
quickly; it is capped at 512 MB. If forwarding does not start, run
`Restart-Service WinRM` on the source, or reboot it.

## 4. Credential Guard / VBS (opt-in, preflight-gated)

**Control:** When `HARDENING_CREDENTIAL_GUARD=1`, the member server is
configured for virtualization-based security and Credential Guard
(`EnableVirtualizationBasedSecurity=1`, `RequirePlatformSecurityFeatures=1`,
`LsaCfgFlags=2`, which is enabled **without** a UEFI lock so it is reversible).
Before changing anything, the script checks that the machine is not a DC, is
Server 2019 or later, boots UEFI with Secure Boot, and exposes virtualization
support. If any check fails it records a `SKIP` with the reason and changes
nothing. After the reboot, `21-Test-CredentialGuard.ps1` confirms through
`Win32_DeviceGuard` that VBS is *running* and that Credential Guard is among
the running services.

**Why:** Credential Guard moves domain credential secrets (NTLM hashes and
Kerberos TGTs) into an isolated process that the normal OS, and an
administrator-level attacker, cannot read directly.

**Attack it mitigates:** Credential theft from LSASS memory (for example with
Mimikatz-style tooling), which is the usual first step in lateral movement and
privilege escalation. Pair with the Sysmon Event 10 detection above.

**How to verify:**

```powershell
(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard).SecurityServicesRunning
# Expect the array to contain 1
```

**Cost/trade-off and limits:**

- Not supported on domain controllers, so it is never applied to `dc01-hardened`.
- Needs hardware virtualization exposed to the guest. On libvirt this means
  `host-passthrough` CPU mode with nested virtualization enabled on the host,
  UEFI firmware (OVMF), and Secure Boot. Many Windows Vagrant boxes are BIOS
  based and will `SKIP`. The libvirt UEFI/Secure Boot and VirtualBox
  nested-virtualization setup is host specific and is **not** validated by
  this repository's CI.
- Credential Guard blocks some legacy authentication (unconstrained Kerberos
  delegation, NTLMv1, and others). Test your workloads.
- The "no false confidence" rule: a configured-but-not-running result is
  reported as `FAIL`, never as success.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| LAPS script reports a missing `LAPS` module | Base box lacks the April 2023 or later update |
| `Update-LapsADSchema` access denied | Provisioning account is not in Schema Admins |
| Domain join fails | DC not provisioned first, wrong `LAB_DC_IP`, or the OU is missing |
| LAPS verify times out | Computer is not in the LabServers OU or the GPO is not linked there |
| Sysmon falls back to `bundled` | No internet in the guest, or Sysmon rejected the downloaded schema version |
| No forwarded events | Source not rebooted/WinRM not restarted, FQDN does not resolve, or TCP 5985 blocked |
| Credential Guard `SKIP` | See the reason printed; usually BIOS firmware, no Secure Boot, or no nested virtualization |

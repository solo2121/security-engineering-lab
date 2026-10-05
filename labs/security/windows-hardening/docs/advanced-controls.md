# Advanced Controls: LAPS, Sysmon + WEF, Credential Guard

This document covers the opt-in controls added after the `v0.1.0` MVP baseline.
They use the same format as the [hardening guide](hardening-guide.md):
**Control, Why, Attack it mitigates or detects, How to verify, Cost/trade-off.**

These controls are **off by default**. Nothing changes for an existing
`vagrant up` unless you export `HARDENING_ADVANCED=1`.

| Control | Type | Default when `HARDENING_ADVANCED=1` | Needs |
| --- | --- | --- | --- |
| Windows LAPS | Mitigation | On | `LAB_PROFILE=full` (the member server is the machine whose password is managed) |
| Sysmon | Detection | On | Internet for the first install (Sysinternals), or a pre-seeded host |
| Windows Event Forwarding | Detection | On | `LAB_PROFILE=full` (`win-member` is the collector; both VMs are sources) |
| Credential Guard / VBS | Mitigation | **Off**; also needs `HARDENING_CREDENTIAL_GUARD=1` | Nested virtualization and UEFI/Secure Boot in the guest; member server only |

## Topology

No new VM is added. The existing two-VM `LAB_PROFILE=full` layout is used:

```
dc01-hardened  domain controller   LAPS schema/OU/GPO, Sysmon, WEF source
win-member     member server       moved into the LabServers OU; LAPS client,
                                   WEF collector, Sysmon, Credential Guard (opt-in)
```

`win-member` plays three roles to keep the footprint small. For a larger lab,
split the collector onto its own VM and change `collector_fqdn` in the
Vagrantfile's `ADVANCED_SETTINGS`. In the default `minimal` profile only the DC
exists, so only the LAPS preparation and Sysmon are applied; forwarding and the
LAPS client need `LAB_PROFILE=full`.

## Prerequisites

- The `vagrant-reload` plugin (the lab already requires it).
- A Windows Server 2022 box with the **April 2023 or later cumulative update**
  (needed for built-in Windows LAPS). The LAPS script stops with a clear
  message if the cmdlets are missing.
- Internet access from the guests for the first Sysmon install (the Sysinternals
  download and, by default, the community config).
- `win-member` memory defaults to 4096 MB when `HARDENING_ADVANCED=1` (2048 MB
  otherwise). Override with `WIN_MEMBER_MEMORY`.

## Usage

The Vagrantfile is already wired to `provision/advanced/vagrant_advanced.rb`.
Enable the controls with environment variables on the host; no other change is
needed:

```bash
cd labs/security/windows-hardening
export HARDENING_ADVANCED=1
LAB_PROFILE=full vagrant up --provider=libvirt   # dc01-hardened first, then win-member
```

Add `HARDENING_CREDENTIAL_GUARD=1` to also attempt Credential Guard (see
section 4 for why it may skip). For an already-running lab, run
`vagrant provision <vm>` for each VM instead of rebuilding it, DC first.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `HARDENING_ADVANCED` | unset | `1` enables LAPS, Sysmon, and WEF |
| `HARDENING_CREDENTIAL_GUARD` | unset | `1` also attempts Credential Guard on `win-member` |
| `HARDENED_DOMAIN_ADMIN_PASSWORD` | the lab's documented domain admin password | Used to move `win-member` into the OU, to verify LAPS escrow, and as a fallback for the schema extension |
| `LAB_SERVERS_OU` | `LabServers` | OU that holds LAPS-managed servers |
| `SYSMON_CONFIG_SOURCE` | `swift` | `swift`, `modular`, or `bundled` |
| `SYSMON_CONFIG_SHA256` | unset | Pin the downloaded config; a mismatch is fatal |
| `HARDENING_STRICT` | `0` | `1` makes verification failures fail `vagrant up` |

The domain name, DC IP, and collector name come from the Vagrantfile constants
(`HARDENED_DOMAIN_NAME`, `DC01_HARDENED_IP`, and `win-member`), so they follow
any overrides you already use.

---

## 1. Windows LAPS

**Control:** The DC extends the AD schema (`Update-LapsADSchema`), creates the
`LabServers` OU, grants computers in it permission to write their own password
(`Set-LapsADComputerSelfPermission`), and links a GPO that enables Windows LAPS
with AD backup, a 20-character complex password, and a 30-day rotation. The
lab's own provisioner joins `win-member` into the default Computers container,
which cannot have a GPO linked, so `01-Move-To-LabOu.ps1` moves its computer
object into the OU. The built-in Administrator is managed; the `vagrant`
account is deliberately not, so rotation cannot lock Vagrant out. If the domain
functional level is 2016 or higher, AD password encryption is enabled as well.

**Why:** A shared local administrator password means one compromised machine
gives an attacker administrative access to every machine that shares it. LAPS
makes each machine's local administrator password unique and rotating, stored
in AD with access controlled by ACLs.

**Attack it mitigates:** Lateral movement by reusing a local administrator
credential or hash across machines (pass-the-hash with a shared local admin).
Compare with the credential attacks in the AD pentest lab's
[attack guide](../../active-directory/base/docs/attack-guide.md#5-credential-attacks).

**How to verify:** The provisioner prints `PASS` when the escrow is confirmed.
Manually, on `dc01-hardened` (or any machine with the LAPS module and
appropriate rights):

```powershell
Get-LapsADPassword -Identity win-member -AsPlainText
# Expect: Account Administrator, a 20-character password, and a future ExpirationTimestamp
```

On `win-member`, `Get-WinEvent -LogName Microsoft-Windows-LAPS/Operational`
shows policy processing and the AD update.

**Cost/trade-off:** Domain admins can read these passwords by default; in a
real deployment, scope the read permission with `Set-LapsADReadPasswordPermission`.
LAPS here does not manage the DC's DSRM password (possible with Windows LAPS
but out of scope for this change).

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
Get-Service Sysmon64                              # Running
Get-Content C:\ProgramData\LabSysmon\state.json   # active config and its SHA-256
Get-WinEvent -LogName Microsoft-Windows-Sysmon/Operational -MaxEvents 5
```

**Cost/trade-off:** Added log volume and a small CPU cost. The default config
download is unpinned unless you set `SYSMON_CONFIG_SHA256`; the script prints
the hash of what it fetched so you can pin it. Check the license and
attribution terms of any community config before redistributing it.

## 3. Windows Event Forwarding

**Control:** `win-member` enables the Windows Event Collector service and
registers a source-initiated subscription (`LabBaseline`, see
`provision/advanced/config/wef-subscription.xml`) that accepts Domain Computers.
Every machine sets the Subscription Manager policy to the collector, lets
`NETWORK SERVICE` read the Security and Sysmon logs through Event Log Readers,
and enables PowerShell script block logging. Forwarded: all Sysmon events,
selected Security events (4624, 4625, 4648, 4662, 4672, 4697, 4698, 4720, 4724,
4728, 4732, 4768, 4769, 4771, 4776, 4886, 4887, 5136), service installs (7045),
PowerShell 4103/4104, and NTLM audit events. They land in `ForwardedEvents` on
the collector.

**Why:** Logs that stay on the machine an attacker controls can be cleared or
ignored. Central collection gives one place to look and survives local
tampering.

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

**Control:** When `HARDENING_CREDENTIAL_GUARD=1`, `win-member` is configured for
virtualization-based security and Credential Guard
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
- Needs hardware virtualization exposed to the guest and UEFI with Secure Boot.
  The lab already sets `host-passthrough` and `nested = true` on libvirt, but it
  does not configure UEFI firmware, and a Windows image installed under BIOS
  cannot be switched to UEFI afterwards. With the current
  `peru/windows-server-2022-standard-x64-eval` box, expect a `SKIP` that names
  the firmware as the reason. Making it run requires a UEFI-based Windows box
  plus OVMF/Secure Boot settings on the VM; that setup is host specific and is
  **not** validated by this repository's CI.
- Credential Guard blocks some legacy authentication (unconstrained Kerberos
  delegation, NTLMv1, and others). Test your workloads.
- A configured-but-not-running result is reported as `FAIL`, never as success.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| LAPS script reports a missing `LAPS` module | Base box lacks the April 2023 or later update |
| `Update-LapsADSchema` access denied | The provisioning account is not in Schema Admins; the script retries as the domain admin over loopback WinRM, so check `HARDENED_DOMAIN_ADMIN_PASSWORD` |
| Move to OU fails | `dc01-hardened` was not provisioned with `HARDENING_ADVANCED=1` first (it creates the OU), or the admin password override is wrong |
| LAPS verify times out | The computer is not in the LabServers OU or the GPO is not linked there |
| Sysmon falls back to `bundled` | No internet in the guest, or Sysmon rejected the downloaded schema version |
| No forwarded events | Source not rebooted/WinRM not restarted, `win-member.<domain>` does not resolve, or TCP 5985 blocked |
| Credential Guard `SKIP` | See the reason printed; usually BIOS firmware, no Secure Boot, or no nested virtualization |

# Windows Server Hardening Lab

**Status: Experimental (v0.1.0 MVP).** This lab is new and has not had the
same amount of real-world testing as the AD pentest labs. Validate it on
your own hardware, and open an issue if something in the provisioning
doesn't match what's described here.

A defensive counterpart to
[`labs/security/active-directory/base/`](../active-directory/base/): the
same Windows Server 2022 base box and Active Directory promotion pattern,
but with a CIS-benchmark-inspired hardening baseline applied instead of the
AD pentest lab's intentional misconfigurations. Where the AD pentest lab
teaches you to find and exploit weaknesses, this lab teaches you to
recognize and apply the corresponding fixes — then verify they hold.

---

## Table of Contents

- [Who this is for](#who-this-is-for)
- [What's included](#whats-included)
- [Lab profiles](#lab-profiles)
- [Advanced controls](#advanced-controls)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Validating the hardening](#validating-the-hardening)
- [Attack-to-mitigation mapping](#attack-to-mitigation-mapping)
- [Credentials](#credentials)
- [Known limitations](#known-limitations)
- [Reset and cleanup](#reset-and-cleanup)
- [Troubleshooting](#troubleshooting)

## Who this is for

Learners who have already worked through the
[AD Pentest Lab](../active-directory/base/) attack guide and want to see
the mitigation side: what changes on a domain controller to close each
attack path, and how to confirm the fix actually worked rather than taking
it on faith.

## What's included

| VM | Role | Profile |
|---|---|---|
| `dc01-hardened` | Windows Server 2022 domain controller with the hardening baseline applied | Always on |
| `win-member` | Domain-joined member server, for testing lateral-movement resistance | `LAB_PROFILE=full` only |

See [`docs/hardening-guide.md`](docs/hardening-guide.md) for the full list
of controls applied and why each one matters.

## Lab profiles

```bash
vagrant up                    # dc01-hardened only (default, "minimal")
LAB_PROFILE=full vagrant up   # dc01-hardened + win-member
```

## Advanced controls

Opt-in and off by default:

```bash
export HARDENING_ADVANCED=1
LAB_PROFILE=full vagrant up --provider=libvirt
```

This adds Windows LAPS, Sysmon with Windows Event Forwarding (`win-member` is
the collector), and, with `HARDENING_CREDENTIAL_GUARD=1`, a preflight-gated
Credential Guard attempt. See
[`docs/advanced-controls.md`](docs/advanced-controls.md) for what each control
does, how to verify it, and its limits. `win-member` gets 4 GB of RAM by
default when these controls are enabled.

## Prerequisites

Same host requirements as the [AD Pentest Lab](../active-directory/base/):

- Linux host with KVM/QEMU + libvirt (primary), or a compatible Intel/AMD
  x86_64 host with VirtualBox.
- 8 GB RAM minimum for `dc01-hardened` alone; 16 GB+ recommended for the
  `full` profile.
- ~60 GB free disk for `dc01-hardened`, ~100 GB for the `full` profile.

Run `../../../scripts/check-prerequisites.sh --all` from the repo root
before deploying, same as the other labs.

## Quick start

```bash
cd labs/security/windows-hardening
vagrant up --provider=libvirt
vagrant status
```

Deployment follows the same phased pattern as `dc01` in the AD pentest
lab (WinRM bootstrap → basic setup → reboot → AD promotion → reboot →
hardening baseline), so expect a similar build time: roughly 30–45 minutes
for `dc01-hardened` alone.

## Validating the hardening

The synced folder is disabled on `dc01-hardened` (same as `dc01` in the AD
pentest lab), so
[`scripts/validate-hardening.ps1`](scripts/validate-hardening.ps1) is not
automatically present inside the VM — copy it in explicitly, then run it:

```bash
# From the lab directory on your host
vagrant winrm-config dc01-hardened   # confirm host/port/credentials

# Copy the script in over WinRM (requires the winrm-fs gem; install once with:
# vagrant plugin install winrm-fs)
vagrant upload scripts/validate-hardening.ps1 C:/validate-hardening.ps1 dc01-hardened

# Run it
vagrant winrm dc01-hardened -e "powershell -ExecutionPolicy Bypass -File C:\validate-hardening.ps1"
```

If `vagrant upload` isn't available in your Vagrant version, open a console
or RDP session to the VM and paste the script's contents into a PowerShell
window directly. It checks each control independently (LLMNR, NetBIOS, SMB
signing, NTLM restriction, Print Spooler, SMBv1, Defender real-time
protection, audit policy categories, password policy) and prints a
per-control pass/fail table plus an overall compliance score (percentage
of controls passed) — it does not modify anything.

See [`docs/hardening-guide.md`](docs/hardening-guide.md) for what each
check means and how to remediate a failure manually.

## Attack-to-mitigation mapping

Every control in this lab maps to a specific technique documented
elsewhere in this repository:

| Control | Mitigates | Attack reference | Detection reference |
|---|---|---|---|
| LLMNR / NetBIOS disabled | Responder-style credential capture | [`attack-guide.md` §4 Initial Access](../active-directory/base/docs/attack-guide.md#4-initial-access) | [`detection-and-blue-team.md` §3](../../../docs/guides/security/detection-and-blue-team.md#3-reconnaissance-detection) |
| SMB signing required | NTLM relay attacks | [`attack-guide.md` §5 Credential Attacks](../active-directory/base/docs/attack-guide.md#5-credential-attacks) | [`detection-and-blue-team.md` §4](../../../docs/guides/security/detection-and-blue-team.md#4-credential-attack-detection) |
| NTLMv1/LM refused | NTLM downgrade attacks | [`attack-guide.md` §5](../active-directory/base/docs/attack-guide.md#5-credential-attacks) | [`detection-and-blue-team.md` §4](../../../docs/guides/security/detection-and-blue-team.md#4-credential-attack-detection) |
| Print Spooler disabled | PrintNightmare (CVE-2021-1675/34527) | [`attack-guide.md` §7 Modern AD Attacks](../active-directory/base/docs/attack-guide.md#7-modern-ad-attacks) | [`detection-and-blue-team.md` §6](../../../docs/guides/security/detection-and-blue-team.md#6-modern-ad-attack-detection) |
| SMBv1 disabled | Legacy SMB exploitation | — | — |
| Defender real-time protection enabled | General malware/tooling execution | (AD pentest lab disables this intentionally) | — |
| Audit policy hardened (Kerberos, DS access/changes, logon, cert services) | Blind spots for Kerberoasting, AS-REP roasting, DCSync, AD CS abuse | [`attack-guide.md` §5–6](../active-directory/base/docs/attack-guide.md#5-credential-attacks) | [`detection-and-blue-team.md` §1, §4, §5](../../../docs/guides/security/detection-and-blue-team.md#1-lab-monitoring-setup) |
| Domain password policy hardened (14-char min, complexity, lockout) | Password spraying | [`attack-guide.md` §4](../active-directory/base/docs/attack-guide.md#4-initial-access) | [`detection-and-blue-team.md` §4](../../../docs/guides/security/detection-and-blue-team.md#4-credential-attack-detection) |

Section anchors above assume the current `attack-guide.md` and
`detection-and-blue-team.md` heading structure — if either doc is
restructured, re-check these links (`scripts/check_doc_references.py`
covers backtick-quoted filenames but not `#anchor` fragments).

## Credentials

See [`docs/lab-credentials.md`](docs/lab-credentials.md). Same
"intentional training credentials, do not reuse" framing as the AD pentest
lab's credential matrix — these are deliberately not production-strength,
just stronger than the intentionally-weak AD pentest lab baseline.

## Known limitations

- **MVP scope, not full domain parity.** No OUs, no seeded user population,
  no AD CS server, no additional service VMs. This lab is about the
  hardening controls, not about replicating the AD pentest lab's full
  environment defensively.
- **NTLM restriction is audit-only in this baseline.** `RestrictReceivingNTLMTraffic`
  is set to audit rather than deny, so you can review what NTLM traffic your
  own tooling generates before enforcing a hard "Deny All." See
  `docs/hardening-guide.md` for how to move to enforcement once you've
  reviewed the audit log.
- **Not a certified CIS Benchmark pass.** The controls here are CIS-inspired
  and mapped to specific attacks this repo's AD pentest lab teaches, not a
  full, certified benchmark implementation. Treat it as a solid teaching
  baseline, not a compliance artifact.
- **No automated attack-resistance test against the AD pentest lab yet.**
  Running the AD pentest lab's Responder/Kerberoasting/NTLM-relay steps
  against this lab's `dc01-hardened` to confirm each mitigation holds is a
  manual exercise for now (see `docs/hardening-guide.md`) — there's no
  cross-lab automation for it.
- **Advanced controls are experimental.** LAPS, Sysmon + WEF, and Credential
  Guard (`HARDENING_ADVANCED=1`) have had static validation only, not
  end-to-end runs on real hardware. Credential Guard needs a UEFI/Secure Boot
  guest and is expected to skip with the current BIOS-based base box.

## Reset and cleanup

Same as the other labs — see
[`docs/guides/workflows/lab-reset-and-cleanup.md`](../../../docs/guides/workflows/lab-reset-and-cleanup.md)
for the full set of options (snapshot revert, single-VM rebuild, full
teardown). This lab does not modify host-level networking, so
`vagrant destroy -f` alone returns the host to its pre-lab state.

## Troubleshooting

This lab reuses the AD pentest lab's WinRM bootstrap, static-IP, and AD
promotion pattern, so most deployment issues and fixes in
[`../active-directory/base/README.md`](../active-directory/base/README.md)
(WinRM timeouts, adapter detection, reboot stalls) apply here too. For
issues specific to the hardening baseline itself (a control not applying,
`phase4-hardening-baseline` erroring), check `C:\HARDENING-BASELINE.log`
inside the VM first — it logs each control as it's applied.

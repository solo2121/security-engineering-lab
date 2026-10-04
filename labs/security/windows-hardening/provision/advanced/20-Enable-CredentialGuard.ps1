<#
.SYNOPSIS
  Enable Virtualization-Based Security and Credential Guard, but only when the
  guest can actually run them.

.DESCRIPTION
  Opt-in (HARDENING_CREDENTIAL_GUARD=1). Run on a MEMBER server: Credential
  Guard is not supported on domain controllers, so a DC is skipped.

  Registry values alone prove nothing, so this script first checks the
  prerequisites and SKIPS loudly (recording the reason) when they are not
  met, instead of configuring something that will silently not run. The
  companion 21-Test-CredentialGuard.ps1 verifies the result after the reboot.

  Credential Guard is configured WITHOUT a UEFI lock (LsaCfgFlags = 2) so it
  can be reverted by changing the registry values and rebooting.

  Pass -Force to attempt configuration even when Secure Boot is not detected.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$StateDir = 'C:\ProgramData\LabCredentialGuard'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step   { param([string]$Message) Write-Host "[advanced-controls] $Message" }
function Write-Result { param([string]$Status, [string]$Message) Write-Host ("[{0}] {1}" -f $Status, $Message) }

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$statePath = Join-Path $StateDir 'state.json'

function Save-State {
    param([string]$Status, [string]$Reason)
    ([ordered]@{ status = $Status; reason = $Reason; utc = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json) | Set-Content -Path $statePath -Encoding ASCII
}

function Skip-Control {
    param([string]$Reason)
    Save-State -Status 'skipped' -Reason $Reason
    Write-Result 'SKIP' "Credential Guard not configured: $Reason"
    exit 0
}

# --- Preflight ----------------------------------------------------------------
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$build          = [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber

if ($computerSystem.DomainRole -ge 4) { Skip-Control 'this is a domain controller (Credential Guard is unsupported on DCs).' }
if ($build -lt 17763)                 { Skip-Control "Windows build $build is older than Server 2019 (17763)." }

$firmwareType = $null
try { $firmwareType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType').PEFirmwareType } catch { $firmwareType = $null }
if ($firmwareType -ne 2) { Skip-Control 'the guest boots with BIOS firmware, not UEFI. Use a UEFI box/VM configuration (see docs/advanced-controls.md).' }

$secureBoot = $false
try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { $secureBoot = $false }
if (-not $secureBoot -and -not $Force) {
    Skip-Control 'Secure Boot is not enabled in the guest. Enable it in the VM firmware, or re-run with -Force to try anyway.'
}

$deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$available   = @()
if ($deviceGuard) { $available = @($deviceGuard.AvailableSecurityProperties) }
if ($available -notcontains 1) {
    Skip-Control 'the guest does not expose virtualization support (nested virtualization / CPU passthrough is not enabled on the host).'
}

# --- Configure ----------------------------------------------------------------
Write-Step 'Prerequisites satisfied; enabling VBS and Credential Guard (no UEFI lock).'

$deviceGuardKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
New-Item -Path $deviceGuardKey -Force | Out-Null
New-ItemProperty -Path $deviceGuardKey -Name 'EnableVirtualizationBasedSecurity' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $deviceGuardKey -Name 'RequirePlatformSecurityFeatures'   -Value 1 -PropertyType DWord -Force | Out-Null   # 1 = Secure Boot

$lsaKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
New-ItemProperty -Path $lsaKey -Name 'LsaCfgFlags' -Value 2 -PropertyType DWord -Force | Out-Null   # 2 = enabled without UEFI lock

Save-State -Status 'configured' -Reason 'registry configured; reboot required before it can be verified'
Write-Result 'PASS' 'Credential Guard configured. A reboot is required; run 21-Test-CredentialGuard.ps1 afterwards to verify it is actually running.'

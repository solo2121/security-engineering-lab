<#
.SYNOPSIS
  Verify that Credential Guard is actually running (not just configured).

.DESCRIPTION
  Reads the state written by 20-Enable-CredentialGuard.ps1, then queries
  Win32_DeviceGuard. Prints PASS, FAIL, or SKIP. Failures are non-fatal
  unless HARDENING_STRICT=1.
#>
[CmdletBinding()]
param(
    [string]$StateDir = 'C:\ProgramData\LabCredentialGuard'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Result { param([string]$Status, [string]$Message) Write-Host ("[{0}] {1}" -f $Status, $Message) }

$statePath = Join-Path $StateDir 'state.json'
if (-not (Test-Path -Path $statePath)) {
    Write-Result 'SKIP' 'Credential Guard was not requested on this machine.'
    exit 0
}

$state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
if ($state.status -eq 'skipped') {
    Write-Result 'SKIP' "Credential Guard was skipped at configuration time: $($state.reason)"
    exit 0
}

$deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
if (-not $deviceGuard) {
    Write-Result 'FAIL' 'Win32_DeviceGuard is not available on this machine.'
    if ($env:HARDENING_STRICT -eq '1') { exit 1 }
    exit 0
}

$vbsStatus  = [int]$deviceGuard.VirtualizationBasedSecurityStatus   # 0 off, 1 enabled but not running, 2 running
$running    = @($deviceGuard.SecurityServicesRunning)                # 1 = Credential Guard, 2 = HVCI
$configured = @($deviceGuard.SecurityServicesConfigured)

Write-Host ("  VBS status: {0}; services configured: [{1}]; running: [{2}]" -f $vbsStatus, ($configured -join ','), ($running -join ','))

if ($vbsStatus -eq 2 -and $running -contains 1) {
    Write-Result 'PASS' 'Credential Guard is running (VBS active, LSA isolated).'
    exit 0
}

Write-Result 'FAIL' 'Credential Guard is configured but NOT running. Do not treat this machine as protected.'
Write-Host '  Likely causes: no nested virtualization / CPU passthrough on the host, Secure Boot not active, or the hypervisor did not start.'
Write-Host '  Check System log source Microsoft-Windows-Kernel-Boot and Microsoft-Windows-DeviceGuard events.'
if ($env:HARDENING_STRICT -eq '1') { exit 1 }
exit 0

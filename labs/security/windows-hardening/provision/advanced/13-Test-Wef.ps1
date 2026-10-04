<#
.SYNOPSIS
  Verify that events from other machines are arriving in ForwardedEvents.

.DESCRIPTION
  Run on the collector. Polls ForwardedEvents until at least one Sysmon event
  from a machine other than this one appears, then prints a per-source summary.
  Failures are non-fatal unless HARDENING_STRICT=1.
#>
[CmdletBinding()]
param(
    [ValidateRange(30, 3600)][int]$TimeoutSeconds = 600,
    [string]$SubscriptionId = 'LabBaseline'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Result { param([string]$Status, [string]$Message) Write-Host ("[{0}] {1}" -f $Status, $Message) }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$remote   = @()
do {
    $events = @(Get-WinEvent -LogName 'ForwardedEvents' -MaxEvents 1000 -ErrorAction SilentlyContinue)
    $remote = @($events | Where-Object { $_.MachineName -notlike "$($env:COMPUTERNAME)*" })
    $remoteSysmon = @($remote | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Sysmon' })
    if ($remoteSysmon.Count -gt 0) { break }
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)

if ($remoteSysmon.Count -gt 0) {
    Write-Result 'PASS' "Receiving Sysmon events from $((@($remoteSysmon | Select-Object -ExpandProperty MachineName -Unique)) -join ', ')."
    $remote | Group-Object MachineName, ProviderName | Sort-Object Count -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Host ("  {0,6}  {1}" -f $_.Count, $_.Name) }
    exit 0
}

Write-Result 'FAIL' "No forwarded Sysmon events from other machines after $TimeoutSeconds seconds."
Write-Host 'Troubleshooting:'
Write-Host "  - On this collector:  wecutil gr $SubscriptionId   (lists registered sources and their state)"
Write-Host '  - On a source:        Get-WinEvent Microsoft-Windows-Forwarding/Operational -MaxEvents 10'
Write-Host '  - Confirm the source resolves and reaches the collector FQDN on TCP 5985.'
Write-Host '  - If the source was not rebooted after configuration, run: Restart-Service WinRM'
if ($env:HARDENING_STRICT -eq '1') { exit 1 }
exit 0

<#
.SYNOPSIS
  Move this (already domain-joined) member server into the lab servers OU.

.DESCRIPTION
  The lab's own win-member provisioner joins the domain into the default
  Computers container, which cannot have a GPO linked to it. Windows LAPS is
  delivered by a GPO linked to the lab servers OU, so the computer object is
  moved there. Idempotent. Uses ADSI with the lab domain admin credentials from
  the host environment, so it does not need RSAT on the member server.

  A reboot afterwards (vagrant-reload) lets the machine pick up its new
  policy scope cleanly.
#>
[CmdletBinding()]
param(
    [string]$Domain        = $env:LAB_DOMAIN,
    [string]$DcIp          = $env:LAB_DC_IP,
    [string]$AdminUser     = $(if ($env:LAB_DOMAIN_ADMIN) { $env:LAB_DOMAIN_ADMIN } else { 'Administrator' }),
    [string]$AdminPassword = $env:LAB_DOMAIN_ADMIN_PASSWORD,
    [string]$ServersOuName = $(if ($env:LAB_SERVERS_OU) { $env:LAB_SERVERS_OU } else { 'LabServers' })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "[advanced-controls] $Message" }

foreach ($pair in @(@('LAB_DOMAIN', $Domain), @('LAB_DC_IP', $DcIp), @('LAB_DOMAIN_ADMIN_PASSWORD', $AdminPassword))) {
    if ([string]::IsNullOrWhiteSpace($pair[1])) { throw "Missing required setting $($pair[0])." }
}

if (-not (Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
    throw 'This machine is not domain-joined yet. The lab phase1-domain-join provisioner must run first.'
}

$domainDn = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$ouDn     = "OU=$ServersOuName,$domainDn"
$upn      = "$AdminUser@$Domain"

$root     = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DcIp/$domainDn", $upn, $AdminPassword)
$searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
$searcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$env:COMPUTERNAME`$))"
[void]$searcher.PropertiesToLoad.Add('distinguishedName')

$deadline = (Get-Date).AddMinutes(5)
$result   = $null
do {
    try { $result = $searcher.FindOne() } catch { Write-Step "AD query not ready: $($_.Exception.Message)" }
    if (-not $result) { Start-Sleep -Seconds 10 }
} while (-not $result -and (Get-Date) -lt $deadline)
if (-not $result) { throw "Computer object $env:COMPUTERNAME not found in $Domain." }

$currentDn = [string]$result.Properties['distinguishedname'][0]
if ($currentDn -like "*,$ouDn") {
    Write-Step "Already in $ouDn."
    return
}

$target = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DcIp/$ouDn", $upn, $AdminPassword)
try { $null = $target.NativeObject }
catch { throw "OU $ouDn does not exist yet. Provision dc01-hardened with HARDENING_ADVANCED=1 first (it creates the OU). $($_.Exception.Message)" }

Write-Step "Moving $currentDn to $ouDn ..."
$computer = $result.GetDirectoryEntry()
$computer.MoveTo($target)
Write-Step 'Moved. A reboot is recommended before verifying LAPS (handled by the reload provisioner).'

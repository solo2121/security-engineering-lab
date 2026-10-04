<#
.SYNOPSIS
  Join a member server to the lab domain, placing it in the lab servers OU.

.DESCRIPTION
  Run on the member server (srv01-hardened) after the domain controller has
  been provisioned. Settings come from environment variables set on the Vagrant
  host (see docs/advanced-controls.md). No credentials are stored in the repo.

  The reboot required by the join is performed by the vagrant-reload
  provisioner that follows this script.
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

function Assert-Setting {
    param([string]$Value, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required setting $Name. Export it on the Vagrant host before 'vagrant up' (see docs/advanced-controls.md)."
    }
}

Assert-Setting $Domain        'LAB_DOMAIN'
Assert-Setting $DcIp          'LAB_DC_IP'
Assert-Setting $AdminPassword 'LAB_DOMAIN_ADMIN_PASSWORD'

if ((Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
    Write-Step 'Already domain-joined; nothing to do.'
    return
}

# Point DNS at the DC on the interface that routes to it (not the NAT adapter).
$ifIndex = (Find-NetRoute -RemoteIPAddress $DcIp | Select-Object -First 1).InterfaceIndex
Write-Step "Setting DNS server $DcIp on interface index $ifIndex."
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $DcIp

Write-Step "Waiting for LDAP on $DcIp ..."
$deadline = (Get-Date).AddMinutes(10)
$reachable = $false
do {
    $reachable = (Test-NetConnection -ComputerName $DcIp -Port 389 -WarningAction SilentlyContinue).TcpTestSucceeded
    if (-not $reachable) { Start-Sleep -Seconds 10 }
} while (-not $reachable -and (Get-Date) -lt $deadline)
if (-not $reachable) { throw "Domain controller $DcIp did not answer on TCP 389 within 10 minutes." }

$null = Resolve-DnsName -Name $Domain -Server $DcIp -ErrorAction Stop

$domainDn = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$ouDn     = "OU=$ServersOuName,$domainDn"

# The password comes from the host environment, so plaintext conversion is expected here.
$secure     = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$Domain\$AdminUser", $secure)

Write-Step "Joining $Domain (OU: $ouDn) ..."
try {
    Add-Computer -DomainName $Domain -OUPath $ouDn -Credential $credential -Force
}
catch {
    throw "Domain join failed. If the OU does not exist yet, provision the DC first (it creates '$ServersOuName'). Original error: $($_.Exception.Message)"
}

Write-Step 'Join complete. A reboot is required (handled by the reload provisioner).'

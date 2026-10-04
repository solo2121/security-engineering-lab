<#
.SYNOPSIS
  Prepare Active Directory and Group Policy for Windows LAPS.

.DESCRIPTION
  Run on the domain controller. Idempotent. Performs:
    1. AD schema extension (Update-LapsADSchema) if needed.
    2. Creates the lab servers OU if missing.
    3. Grants computers in that OU permission to write their own password.
    4. Creates and links a GPO that enables Windows LAPS (AD backup).

  Uses Windows LAPS (built in to Windows Server with the April 2023 or later
  cumulative update), not the legacy Microsoft LAPS MSI.

  The managed account is the built-in local Administrator. The 'vagrant' user
  that Vagrant connects with is intentionally NOT managed, so password rotation
  never locks Vagrant out.
#>
[CmdletBinding()]
param(
    [string]$ServersOuName = $(if ($env:LAB_SERVERS_OU) { $env:LAB_SERVERS_OU } else { 'LabServers' }),
    [string]$GpoName       = 'Lab - Windows LAPS',
    [ValidateRange(1, 365)][int]$PasswordAgeDays = 30,
    [ValidateRange(14, 64)][int]$PasswordLength  = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "[advanced-controls] $Message" }

foreach ($module in 'ActiveDirectory', 'GroupPolicy', 'LAPS') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "PowerShell module '$module' is not available. Windows LAPS needs the April 2023 (or later) cumulative update on Windows Server 2019/2022. Update the base box or run Windows Update first."
    }
    Import-Module $module -ErrorAction Stop
}

$domain   = Get-ADDomain
$domainDn = $domain.DistinguishedName
$rootDse  = Get-ADRootDSE

# 1. Schema ---------------------------------------------------------------
$schemaAttribute = Get-ADObject -SearchBase $rootDse.schemaNamingContext `
    -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -ErrorAction SilentlyContinue
if ($schemaAttribute) {
    Write-Step 'Windows LAPS schema attributes already present.'
}
else {
    Write-Step 'Extending the AD schema for Windows LAPS ...'
    Update-LapsADSchema -Confirm:$false
}

# 2. OU -------------------------------------------------------------------
$ouDn = "OU=$ServersOuName,$domainDn"
try {
    $null = Get-ADOrganizationalUnit -Identity $ouDn
    Write-Step "OU $ouDn already exists."
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Step "Creating OU $ouDn ..."
    New-ADOrganizationalUnit -Name $ServersOuName -Path $domainDn -ProtectedFromAccidentalDeletion $false
}

# 3. Self-permission for computers in the OU --------------------------------
Write-Step 'Granting computers in the OU permission to update their own LAPS password ...'
$null = Set-LapsADComputerSelfPermission -Identity $ouDn

# 4. GPO ------------------------------------------------------------------
$gpo = $null
try { $gpo = Get-GPO -Name $GpoName } catch { $gpo = $null }
if (-not $gpo) {
    Write-Step "Creating GPO '$GpoName' ..."
    $gpo = New-GPO -Name $GpoName -Comment 'Windows LAPS: back up the local Administrator password to Active Directory.'
}

# AD password encryption needs domain functional level 2016 or later.
$encryptionSupported = @('Windows2016Domain', 'Windows2025Domain') -contains $domain.DomainMode.ToString()

$policyKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
$settings  = [ordered]@{
    BackupDirectory    = 2    # 2 = Active Directory
    PasswordAgeDays    = $PasswordAgeDays
    PasswordLength     = $PasswordLength
    PasswordComplexity = 4    # large + small letters, digits, special characters
}
if ($encryptionSupported) { $settings['ADPasswordEncryptionEnabled'] = 1 }

foreach ($name in $settings.Keys) {
    $null = Set-GPRegistryValue -Name $GpoName -Key $policyKey -ValueName $name -Type DWord -Value $settings[$name]
}

$existingLink = @((Get-GPInheritance -Target $ouDn).GpoLinks | Where-Object { $_.DisplayName -eq $GpoName })
if ($existingLink.Count -eq 0) {
    Write-Step "Linking '$GpoName' to $ouDn ..."
    $null = New-GPLink -Name $GpoName -Target $ouDn -LinkEnabled Yes
}

Write-Step ("Windows LAPS ready. Password encryption in AD: {0}." -f $(if ($encryptionSupported) { 'enabled' } else { 'not available (domain functional level below 2016)' }))

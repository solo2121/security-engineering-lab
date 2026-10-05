<#
.SYNOPSIS
  Prepare Active Directory and Group Policy for Windows LAPS.

.DESCRIPTION
  Run on the domain controller. Idempotent. Performs:
    1. AD schema extension (Update-LapsADSchema) if needed.
    2. Creates the lab servers OU if missing.
    3. Grants computers in that OU permission to write their own password.
    4. Creates and links a GPO that enables Windows LAPS (AD backup).

  Schema changes need Schema Admins. The account Vagrant uses may not be a
  member, so if the direct attempt fails and LAB_DOMAIN_ADMIN_PASSWORD is set,
  the same work is retried over a loopback WinRM session as the domain admin.

  Uses Windows LAPS (built in to Windows Server with the April 2023 or later
  cumulative update), not the legacy Microsoft LAPS MSI. The managed account is
  the built-in local Administrator; the 'vagrant' account is intentionally NOT
  managed, so password rotation never locks Vagrant out.
#>
[CmdletBinding()]
param(
    [string]$ServersOuName = $(if ($env:LAB_SERVERS_OU) { $env:LAB_SERVERS_OU } else { 'LabServers' }),
    [string]$GpoName       = 'Lab - Windows LAPS',
    [ValidateRange(1, 365)][int]$PasswordAgeDays = 30,
    [ValidateRange(14, 64)][int]$PasswordLength  = 20,
    [string]$AdminUser     = $(if ($env:LAB_DOMAIN_ADMIN) { $env:LAB_DOMAIN_ADMIN } else { 'Administrator' }),
    [string]$AdminPassword = $env:LAB_DOMAIN_ADMIN_PASSWORD
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "[advanced-controls] $Message" }

# Everything that touches AD lives in one script block so it can be run either
# directly or in a loopback session under different credentials. It returns
# status strings instead of calling helper functions for that reason.
$configure = {
    param([string]$OuName, [string]$Gpo, [int]$AgeDays, [int]$Length)

    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    foreach ($module in 'ActiveDirectory', 'GroupPolicy', 'LAPS') {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "PowerShell module '$module' is not available. Windows LAPS needs the April 2023 (or later) cumulative update on Windows Server 2019/2022. Update the base box or run Windows Update first."
        }
        Import-Module $module -ErrorAction Stop
    }

    $domain   = Get-ADDomain
    $domainDn = $domain.DistinguishedName
    $rootDse  = Get-ADRootDSE

    # 1. Schema
    $schemaAttribute = Get-ADObject -SearchBase $rootDse.schemaNamingContext `
        -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -ErrorAction SilentlyContinue
    if ($schemaAttribute) { 'Windows LAPS schema attributes already present.' }
    else {
        'Extending the AD schema for Windows LAPS ...'
        Update-LapsADSchema -Confirm:$false
    }

    # 2. OU
    $ouDn = "OU=$OuName,$domainDn"
    try {
        $null = Get-ADOrganizationalUnit -Identity $ouDn
        "OU $ouDn already exists."
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        "Creating OU $ouDn ..."
        New-ADOrganizationalUnit -Name $OuName -Path $domainDn -ProtectedFromAccidentalDeletion $false
    }

    # 3. Self-permission for computers in the OU
    'Granting computers in the OU permission to update their own LAPS password ...'
    $null = Set-LapsADComputerSelfPermission -Identity $ouDn

    # 4. GPO
    $gpoObject = $null
    try { $gpoObject = Get-GPO -Name $Gpo } catch { $gpoObject = $null }
    if (-not $gpoObject) {
        "Creating GPO '$Gpo' ..."
        $gpoObject = New-GPO -Name $Gpo -Comment 'Windows LAPS: back up the local Administrator password to Active Directory.'
    }

    # AD password encryption needs domain functional level 2016 or later.
    $encryptionSupported = @('Windows2016Domain', 'Windows2025Domain') -contains $domain.DomainMode.ToString()

    $policyKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
    $settings  = [ordered]@{
        BackupDirectory    = 2    # 2 = Active Directory
        PasswordAgeDays    = $AgeDays
        PasswordLength     = $Length
        PasswordComplexity = 4    # large + small letters, digits, special characters
    }
    if ($encryptionSupported) { $settings['ADPasswordEncryptionEnabled'] = 1 }

    foreach ($name in $settings.Keys) {
        $null = Set-GPRegistryValue -Name $Gpo -Key $policyKey -ValueName $name -Type DWord -Value $settings[$name]
    }

    $existingLink = @((Get-GPInheritance -Target $ouDn).GpoLinks | Where-Object { $_.DisplayName -eq $Gpo })
    if ($existingLink.Count -eq 0) {
        "Linking '$Gpo' to $ouDn ..."
        $null = New-GPLink -Name $Gpo -Target $ouDn -LinkEnabled Yes
    }

    'Windows LAPS ready. Password encryption in AD: {0}.' -f $(if ($encryptionSupported) { 'enabled' } else { 'not available (domain functional level below 2016)' })
}

$arguments = @($ServersOuName, $GpoName, $PasswordAgeDays, $PasswordLength)

try {
    & $configure @arguments | ForEach-Object { Write-Step $_ }
}
catch {
    $directError = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
        throw "Windows LAPS preparation failed: $directError (set LAB_DOMAIN_ADMIN_PASSWORD to retry as the domain admin)."
    }

    Write-Step "Direct attempt failed ($directError). Retrying as $AdminUser over loopback WinRM ..."
    $dnsRoot    = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    $computer   = "$env:COMPUTERNAME.$dnsRoot"
    $credential = New-Object System.Management.Automation.PSCredential(
        "$AdminUser@$dnsRoot",
        (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force))   # password comes from the host environment

    Invoke-Command -ComputerName $computer -Credential $credential -ScriptBlock $configure -ArgumentList $arguments |
        ForEach-Object { Write-Step $_ }
}

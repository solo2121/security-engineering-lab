<#
.SYNOPSIS
  Apply Windows LAPS policy on a member server and verify the password was
  escrowed to Active Directory.

.DESCRIPTION
  Run on the member server after the domain join and reboot. Forces policy
  processing, then polls AD (using the lab domain admin credentials from the
  host environment) until msLAPS-PasswordExpirationTime is populated for this
  computer. The password itself is never read or printed.

  Failures are non-fatal unless HARDENING_STRICT=1.
#>
[CmdletBinding()]
param(
    [string]$Domain        = $env:LAB_DOMAIN,
    [string]$DcIp          = $env:LAB_DC_IP,
    [string]$AdminUser     = $(if ($env:LAB_DOMAIN_ADMIN) { $env:LAB_DOMAIN_ADMIN } else { 'Administrator' }),
    [string]$AdminPassword = $env:LAB_DOMAIN_ADMIN_PASSWORD,
    [ValidateRange(30, 1800)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step   { param([string]$Message) Write-Host "[advanced-controls] $Message" }
function Write-Result { param([string]$Status, [string]$Message) Write-Host ("[{0}] {1}" -f $Status, $Message) }
function Complete-Check {
    param([bool]$Passed)
    if (-not $Passed -and $env:HARDENING_STRICT -eq '1') { exit 1 }
    exit 0
}

foreach ($pair in @(@('LAB_DOMAIN', $Domain), @('LAB_DC_IP', $DcIp), @('LAB_DOMAIN_ADMIN_PASSWORD', $AdminPassword))) {
    if ([string]::IsNullOrWhiteSpace($pair[1])) { throw "Missing required setting $($pair[0])." }
}

Write-Step 'Forcing computer policy refresh and Windows LAPS processing ...'
$null = cmd.exe /c "gpupdate.exe /force /target:computer >nul 2>&1"
if (Get-Command -Name Invoke-LapsPolicyProcessing -ErrorAction SilentlyContinue) {
    Invoke-LapsPolicyProcessing
}

$entry    = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DcIp", "$Domain\$AdminUser", $AdminPassword)
$searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
$searcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$env:COMPUTERNAME`$))"
[void]$searcher.PropertiesToLoad.Add('msLAPS-PasswordExpirationTime')

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$escrowed = $false
do {
    try {
        $result = $searcher.FindOne()
        if ($result -and ($result.Properties.PropertyNames -contains 'mslaps-passwordexpirationtime')) {
            $escrowed = $true
            break
        }
    }
    catch {
        Write-Step "AD query not ready yet: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 10
    if (Get-Command -Name Invoke-LapsPolicyProcessing -ErrorAction SilentlyContinue) { Invoke-LapsPolicyProcessing }
} while ((Get-Date) -lt $deadline)

if ($escrowed) {
    Write-Result 'PASS' "Windows LAPS password for $env:COMPUTERNAME is escrowed in Active Directory."
    Complete-Check $true
}

Write-Result 'FAIL' "No LAPS password found in AD for $env:COMPUTERNAME after $TimeoutSeconds seconds."
Write-Host 'Recent Windows LAPS events on this machine:'
Get-WinEvent -LogName 'Microsoft-Windows-LAPS/Operational' -MaxEvents 5 -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("  [{0}] {1}" -f $_.Id, ($_.Message -split "`r?`n")[0]) }
Write-Host 'Check: computer is in the lab servers OU, the LAPS GPO is linked there, and the DC has the April 2023+ update.'
Complete-Check $false

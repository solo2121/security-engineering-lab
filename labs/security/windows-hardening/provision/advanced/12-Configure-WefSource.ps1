<#
.SYNOPSIS
  Configure this machine to forward events to the lab WEF collector.

.DESCRIPTION
  Sets the Subscription Manager policy value, lets NETWORK SERVICE read the
  Security and Sysmon logs (via Event Log Readers), and enables PowerShell
  script block logging so Event 4104 exists to be forwarded.

  WinRM is deliberately NOT restarted here: Vagrant is using it to run this
  script. The reload provisioner that follows applies the change cleanly.
  This is the local-policy equivalent of the usual "Configure target
  Subscription Manager" GPO; in a larger lab, deliver it by GPO instead.
#>
[CmdletBinding()]
param(
    [string]$CollectorFqdn = $env:LAB_COLLECTOR_FQDN,
    [ValidateRange(30, 3600)][int]$RefreshSeconds = 60
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step   { param([string]$Message) Write-Host "[advanced-controls] $Message" }
function Write-Result { param([string]$Status, [string]$Message) Write-Host ("[{0}] {1}" -f $Status, $Message) }

function Invoke-Native {
    param([string]$Path, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Path @Arguments 2>&1 | Out-String
        $code   = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    [pscustomobject]@{ ExitCode = $code; Output = $output }
}

if ([string]::IsNullOrWhiteSpace($CollectorFqdn)) {
    throw 'Missing LAB_COLLECTOR_FQDN (or set LAB_DOMAIN so the default srv01-hardened.<domain> can be derived).'
}

# 1. Subscription manager --------------------------------------------------------
$managerKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'
New-Item -Path $managerKey -Force | Out-Null
$managerValue = "Server=http://${CollectorFqdn}:5985/wsman/SubscriptionManager/WEC,Refresh=$RefreshSeconds"
New-ItemProperty -Path $managerKey -Name '1' -Value $managerValue -PropertyType String -Force | Out-Null
Write-Step "Subscription manager set to $CollectorFqdn."

# 2. Let NETWORK SERVICE read the logs ------------------------------------------
$join = Invoke-Native -Path 'net.exe' -Arguments @('localgroup', 'Event Log Readers', 'NT AUTHORITY\NETWORK SERVICE', '/add')
if ($join.ExitCode -ne 0 -and $join.Output -notmatch '1378') {
    throw "Could not add NETWORK SERVICE to Event Log Readers: $($join.Output)"
}

# 3. PowerShell script block logging (source of Event 4104) ----------------------
$sbKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
New-Item -Path $sbKey -Force | Out-Null
New-ItemProperty -Path $sbKey -Name 'EnableScriptBlockLogging' -Value 1 -PropertyType DWord -Force | Out-Null

# 4. WinRM must be running and set to start automatically -------------------------
Set-Service -Name 'WinRM' -StartupType Automatic
if ((Get-Service -Name 'WinRM').Status -ne 'Running') { Start-Service -Name 'WinRM' }

Write-Result 'PASS' "Event forwarding source configured for $CollectorFqdn (takes effect after the next reload)."

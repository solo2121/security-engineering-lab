<#
.SYNOPSIS
  Configure this server as a Windows Event Forwarding (WEF) collector.

.DESCRIPTION
  Enables the Windows Event Collector service, sizes the ForwardedEvents log,
  and registers the source-initiated "LabBaseline" subscription from the XML
  uploaded by the Vagrant file provisioner. Idempotent: an existing
  subscription with the same ID is replaced so edits to the XML take effect.
#>
[CmdletBinding()]
param(
    [string]$SubscriptionFile = 'C:\ProgramData\LabAdvanced\wef-subscription.xml',
    [string]$SubscriptionId   = 'LabBaseline',
    [ValidateRange(64, 2000)][int]$ForwardedEventsMaxMB = 512
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

if (-not (Test-Path -Path $SubscriptionFile)) {
    throw "Subscription file not found: $SubscriptionFile (the Vagrant file provisioner should have uploaded it)."
}

Write-Step 'Enabling the Windows Event Collector service ...'
Set-Service -Name 'Wecsvc' -StartupType Automatic
$qc = Invoke-Native -Path 'wecutil.exe' -Arguments @('qc', '/q')
if ($qc.ExitCode -ne 0) { throw "wecutil qc failed (exit $($qc.ExitCode)): $($qc.Output)" }

$sizeBytes = [int64]$ForwardedEventsMaxMB * 1MB
$null = Invoke-Native -Path 'wevtutil.exe' -Arguments @('sl', 'ForwardedEvents', "/ms:$sizeBytes")

$existing = Invoke-Native -Path 'wecutil.exe' -Arguments @('gs', $SubscriptionId)
if ($existing.ExitCode -eq 0) {
    Write-Step "Replacing existing subscription '$SubscriptionId' ..."
    $del = Invoke-Native -Path 'wecutil.exe' -Arguments @('ds', $SubscriptionId)
    if ($del.ExitCode -ne 0) { throw "wecutil ds failed: $($del.Output)" }
}

$create = Invoke-Native -Path 'wecutil.exe' -Arguments @('cs', $SubscriptionFile)
if ($create.ExitCode -ne 0) { throw "wecutil cs failed (exit $($create.ExitCode)): $($create.Output)" }

$verify = Invoke-Native -Path 'wecutil.exe' -Arguments @('gs', $SubscriptionId)
if ($verify.ExitCode -ne 0) { throw "Subscription '$SubscriptionId' was not found after creation." }

Write-Result 'PASS' "WEF collector ready; subscription '$SubscriptionId' registered (source-initiated, Domain Computers allowed)."

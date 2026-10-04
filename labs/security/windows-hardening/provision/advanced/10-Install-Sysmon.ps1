<#
.SYNOPSIS
  Install (or update the configuration of) Sysmon with a community baseline.

.DESCRIPTION
  Idempotent. The Sysmon binary is downloaded from Microsoft Sysinternals and its
  Authenticode signature is verified before use. The configuration comes from:
    swift    SwiftOnSecurity/sysmon-config (default)
    modular  olafhartong/sysmon-modular (merged sysmonconfig.xml)
    bundled  the small lab baseline shipped in this repository

  If the download fails, or the installed Sysmon rejects the downloaded
  schema, the bundled baseline is used and a WARN is printed. Set
  SYSMON_CONFIG_SHA256 to pin the downloaded config; a mismatch is fatal
  (there is no silent fallback when you pinned a hash).

  Review the license and attribution terms of the community configs before
  redistributing them.
#>
[CmdletBinding()]
param(
    [ValidateSet('swift', 'modular', 'bundled')]
    [string]$ConfigSource  = $(if ($env:SYSMON_CONFIG_SOURCE) { $env:SYSMON_CONFIG_SOURCE } else { 'swift' }),
    [string]$ConfigSha256  = $env:SYSMON_CONFIG_SHA256,
    [string]$BundledConfig = 'C:\ProgramData\LabAdvanced\sysmon-lab-baseline.xml',
    [string]$WorkDir       = 'C:\ProgramData\LabSysmon'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SysmonUrl  = 'https://download.sysinternals.com/files/Sysmon.zip'
$ConfigUrls = @{
    swift   = 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml'
    modular = 'https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig.xml'
}

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

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Resolve the configuration ------------------------------------------------
$configPath  = $null
$configLabel = $ConfigSource

if ($ConfigSource -ne 'bundled') {
    $candidate = Join-Path $WorkDir "sysmon-$ConfigSource.xml"
    $downloaded = $false
    try {
        Write-Step "Downloading $ConfigSource Sysmon config ..."
        Invoke-WebRequest -Uri $ConfigUrls[$ConfigSource] -OutFile $candidate -UseBasicParsing
        $downloaded = $true
    }
    catch {
        Write-Result 'WARN' "Could not download the $ConfigSource config ($($_.Exception.Message)). Falling back to the bundled baseline."
    }

    if ($downloaded) {
        $actualHash = (Get-FileHash -Path $candidate -Algorithm SHA256).Hash
        if ($ConfigSha256) {
            if ($actualHash -ne $ConfigSha256.Trim().ToUpperInvariant()) {
                throw "SHA-256 mismatch for the $ConfigSource config. Expected $ConfigSha256, got $actualHash."
            }
            Write-Step "Config SHA-256 matches the pinned value."
        }
        else {
            Write-Result 'WARN' "Config is not pinned (SYSMON_CONFIG_SHA256 unset). SHA-256 of what was downloaded: $actualHash"
        }
        $null = [xml](Get-Content -Path $candidate -Raw)   # well-formedness check
        $configPath = $candidate
    }
}

if (-not $configPath) {
    if (-not (Test-Path -Path $BundledConfig)) { throw "Bundled Sysmon config not found at $BundledConfig (the Vagrant file provisioner should have uploaded it)." }
    $configPath  = $BundledConfig
    $configLabel = 'bundled'
}

# --- Install or reconfigure ---------------------------------------------------
$service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue

if ($service) {
    Write-Step 'Sysmon already installed; applying configuration.'
    $installedExe = Join-Path $env:SystemRoot 'Sysmon64.exe'
    $run = { param($cfg) Invoke-Native -Path $installedExe -Arguments @('-c', $cfg) }
}
else {
    Write-Step 'Downloading Sysmon from Sysinternals ...'
    $zip = Join-Path $WorkDir 'Sysmon.zip'
    $bin = Join-Path $WorkDir 'bin'
    Invoke-WebRequest -Uri $SysmonUrl -OutFile $zip -UseBasicParsing
    if (Test-Path -Path $bin) { Remove-Item -Path $bin -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $bin -Force

    $exe = Join-Path $bin 'Sysmon64.exe'
    $signature = Get-AuthenticodeSignature -FilePath $exe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Sysmon64.exe failed Authenticode verification (status: $($signature.Status)). Refusing to install."
    }
    Write-Step 'Sysmon64.exe signature verified (Microsoft Corporation).'
    $run = { param($cfg) Invoke-Native -Path $exe -Arguments @('-accepteula', '-i', $cfg) }
}

$result = & $run $configPath
if ($result.ExitCode -ne 0 -and $configLabel -ne 'bundled') {
    Write-Result 'WARN' "Sysmon rejected the $configLabel config (exit $($result.ExitCode)). Falling back to the bundled baseline."
    Write-Host $result.Output
    if (-not (Test-Path -Path $BundledConfig)) { throw "Bundled Sysmon config not found at $BundledConfig." }
    $configPath  = $BundledConfig
    $configLabel = 'bundled'
    $service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($service) {
        $result = Invoke-Native -Path (Join-Path $env:SystemRoot 'Sysmon64.exe') -Arguments @('-c', $configPath)
    }
    else {
        $result = & $run $configPath
    }
}
if ($result.ExitCode -ne 0) { throw "Sysmon failed (exit $($result.ExitCode)):`n$($result.Output)" }

# --- Post-conditions ----------------------------------------------------------
Start-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
$service = Get-Service -Name 'Sysmon64'
if ($service.Status -ne 'Running') { throw "Sysmon64 service is $($service.Status), expected Running." }

$null = Invoke-Native -Path 'wevtutil.exe' -Arguments @('sl', 'Microsoft-Windows-Sysmon/Operational', '/ms:268435456')

$state = [ordered]@{
    configSource = $configLabel
    configSha256 = (Get-FileHash -Path $configPath -Algorithm SHA256).Hash
    installedUtc = (Get-Date).ToUniversalTime().ToString('o')
}
$state | ConvertTo-Json | Set-Content -Path (Join-Path $WorkDir 'state.json') -Encoding ASCII

Write-Result 'PASS' "Sysmon64 running with the '$configLabel' configuration."

$LogDir = "C:\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
$LogFile = "$LogDir\domain-join-@@VM_NAME@@.log"

function Write-Log {
  param($Message)
  $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "$Timestamp - $Message"
  Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

Write-Log "Starting domain join for @@VM_NAME@@"

$maxRetries = 10
$retryCount = 0
$dnsSet = $false

while ($retryCount -lt $maxRetries -and -not $dnsSet) {
  $retryCount++
  try {
    $adapter = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1
    if ($adapter) {
      Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '@@DC_IP@@' -ErrorAction Stop
      $dnsSet = $true
      Write-Log "DNS set to @@DC_IP@@"
    }
  } catch {
    Write-Log "DNS set attempt $retryCount failed, retrying..."
    Start-Sleep -Seconds 10
  }
}

if (-not $dnsSet) {
  Write-Log "ERROR: Failed to set DNS after $maxRetries attempts"
  exit 1
}

if (-not (Test-Connection '@@DC_IP@@' -Count 1 -Quiet)) {
  Write-Log "ERROR: Cannot reach DC at @@DC_IP@@"
  exit 1
}

$sec = ConvertTo-SecureString '@@DOMAIN_JOIN_PASS_SQ@@' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('@@DOMAIN_NETBIOS@@\@@DOMAIN_JOIN_USER@@', $sec)

$joinRetries = 5
$joinCount = 0
$joined = $false

while ($joinCount -lt $joinRetries -and -not $joined) {
  $joinCount++
  try {
    Add-Computer -DomainName "@@DOMAIN_NAME@@" -Credential $cred -Force -ErrorAction Stop
    $joined = $true
    Write-Log "Joined domain @@DOMAIN_NAME@@"
  } catch {
    Write-Log "Domain join attempt $joinCount failed: $_"
    Start-Sleep -Seconds 30
  }
}

if (-not $joined) {
  Write-Log "ERROR: Failed to join domain after $joinRetries attempts"
  exit 1
}

if ($env:COMPUTERNAME -ne '@@VM_NAME@@') {
  Rename-Computer -NewName '@@VM_NAME@@' -Force
  Write-Log "Renamed computer to @@VM_NAME@@"
}

Write-Log "SUCCESS: @@VM_NAME@@ domain join complete"

$LogDir = "C:\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
$LogFile = "$LogDir\wait-for-dc.log"

function Write-Log {
  param($Message)
  $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "$Timestamp - $Message"
  Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

$attempt = 0
$maxAttempts = @@MAX_ATTEMPTS@@
$dcIP = '@@IP@@'

Write-Log "Waiting for Domain Controller at $dcIP..."

while ($attempt -lt $maxAttempts) {
  $attempt++
  if (Test-Connection $dcIP -Count 1 -Quiet) {
    try {
      if (Test-Path "\\$dcIP\C$\DC-FINAL.txt") {
        Write-Log "DC01 is fully configured."
        try {
          Test-WSMan $dcIP -ErrorAction SilentlyContinue | Out-Null
          Write-Log "WinRM is responding on DC01"
          exit 0
        } catch {
          Write-Log "DC reachable but WinRM not responding yet..."
        }
      } else {
        Write-Log "DC reachable but not fully configured yet..."
      }
    } catch {
      Write-Log "Could not access DC share: $_"
    }
  } else {
    Write-Log "DC not reachable yet (attempt $attempt of $maxAttempts)"
  }
  Start-Sleep -Seconds 30
}
Write-Log "ERROR: DC not ready after $maxAttempts attempts"
exit 1

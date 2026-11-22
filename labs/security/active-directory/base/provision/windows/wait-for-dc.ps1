$ErrorActionPreference = 'Continue'
$attempt = 0
$maxAttempts = @@MAX_ATTEMPTS@@
$dcIP = '@@IP@@'

Write-Host "Waiting for Domain Controller at $dcIP to be fully ready..."

while ($attempt -lt $maxAttempts) {
  $attempt++
  Write-Host "Attempt $attempt of $maxAttempts..."

  $ready = $false

  if (Test-Connection $dcIP -Count 1 -Quiet) {
    if (Test-Path "\\$dcIP\C$\DC-FINAL.txt") {
      Write-Host "[OK] DC01 is fully configured and ready."
      $ready = $true
      break
    } else {
      Write-Host "DC01 not fully configured yet... waiting 30s"
    }
  } else {
    Write-Host "DC01 not reachable via ICMP... waiting 30s"
  }

  Start-Sleep -Seconds 30
}

if (-not $ready) {
  Write-Error "Domain Controller not ready after $maxAttempts attempts"
  exit 1
}

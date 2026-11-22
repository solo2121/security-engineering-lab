$ErrorActionPreference = 'Continue'
Write-Host "=============================================="
Write-Host "HEALTH CHECK - @@HOSTNAME_UPPER@@"
Write-Host "=============================================="

$testResult = Test-Connection 127.0.0.1 -Count 2 -Quiet
Write-Host "[CHECK] VM responsiveness: $(if ($testResult) { 'OK' } else { 'FAILED' })"

$winrmStatus = (Get-Service WinRM -ErrorAction SilentlyContinue).Status
Write-Host "[CHECK] WinRM service: $winrmStatus"

$dcTest = Test-Connection @@DC_IP@@ -Count 2 -Quiet
Write-Host "[CHECK] Connectivity to DC: $(if ($dcTest) { 'OK' } else { 'FAILED' })"

if ('@@HOSTNAME@@' -ne 'dc01') {
  $domainTest = Test-ComputerSecureChannel -ErrorAction SilentlyContinue
  Write-Host "[CHECK] Domain trust: $(if ($domainTest) { 'OK' } else { 'FAILED' })"
}

$healthStatus = @{
  hostname = '@@HOSTNAME@@'
  timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  checks = @{
    responsive = $testResult
    winrm = $winrmStatus -eq 'Running'
    dc_connectivity = $dcTest
    domain_trust = if ('@@HOSTNAME@@' -ne 'dc01') { $domainTest } else { $true }
  }
}

$healthStatus | ConvertTo-Json | Out-File "C:\HEALTH-@@HOSTNAME@@.json" -Force

Write-Host "=============================================="
Write-Host "HEALTH CHECK COMPLETE"
Write-Host "=============================================="

$ErrorActionPreference = 'Continue'
Write-Host "=============================================="
Write-Host "DISABLING MANAGEMENT GATEWAY - @@VM_NAME_UPPER@@"
Write-Host "=============================================="

Start-Sleep -Seconds 30

$natAdapter = Get-NetAdapter | Where-Object {
  $_.Status -eq 'Up' -and (
    (Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue |
     Where-Object { $_.IPAddress -like "@@NAT_IP_PREFIX@@" })
  )
} | Select-Object -First 1

if ($natAdapter) {
  $route = Get-NetRoute -InterfaceIndex $natAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
  if ($route) {
    Remove-NetRoute -InterfaceIndex $natAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] Management default gateway removed — VLAN gateway retained"
  } else {
    Write-Host "[INFO] No default gateway on management adapter"
  }
} else {
  Write-Host "[INFO] No management adapter found — VM may already be isolated"
}
Write-Host "=============================================="

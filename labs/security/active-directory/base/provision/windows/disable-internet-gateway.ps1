$ErrorActionPreference = 'Continue'
Write-Host "=============================================="
Write-Host "DISABLING INTERNET GATEWAY - @@VM_NAME_UPPER@@"
Write-Host "=============================================="

Start-Sleep -Seconds 30

$natAdapter = Get-NetAdapter | Where-Object {
  $_.Status -eq 'Up' -and (
    @@NAT_MATCH@@
  )
} | Select-Object -First 1

if ($natAdapter) {
  Write-Host "[OK] Found NAT adapter: $($natAdapter.Name) (Index: $($natAdapter.ifIndex))"
  $natIP = Get-NetIPAddress -InterfaceIndex $natAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
  if ($natIP) {
    Write-Host "[OK] Current NAT IP: $($natIP.IPAddress) (kept for Vagrant management)"
  }

  $route = Get-NetRoute -InterfaceIndex $natAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
  if ($route) {
    Remove-NetRoute -InterfaceIndex $natAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] Default gateway removed - Internet access disabled"
  } else {
    Write-Host "[INFO] No default gateway found on NAT adapter"
  }

  Start-Sleep -Seconds 5
  if (Test-Connection 8.8.8.8 -Count 1 -Quiet) {
    Write-Host "[WARNING] Still has internet access - check configuration"
  } else {
    Write-Host "[OK] Internet unreachable - isolation successful"
  }

  if (Test-Connection @@DC_IP@@ -Count 1 -Quiet) {
    Write-Host "[OK] Lab network still functional (can reach @@DC_IP@@)"
  } else {
    Write-Host "[WARNING] Cannot reach DC - check lab network"
  }
} else {
  Write-Host "[INFO] No NAT adapter found - VM may already be isolated"
  Write-Host "Current network adapters:"
  Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Format-Table Name, Status, LinkSpeed
  Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength
}

Write-Host "=============================================="
Write-Host "INTERNET ISOLATION COMPLETE FOR @@VM_NAME_UPPER@@"
Write-Host "VM can now only communicate on lab network (@@LAB_SUBNET@@)"
Write-Host "Vagrant management still works via NAT IP"
Write-Host "=============================================="

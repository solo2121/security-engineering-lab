# Method 3: Look for adapter named "Ethernet 2" (common for VirtualBox)
$adapter = Get-NetAdapter -Name "Ethernet 2" -ErrorAction SilentlyContinue

if ($adapter) {
  Write-Host "[OK] Found adapter by name: Ethernet 2"
} else {
  # Method 4: Look for adapter named "Ethernet" (VirtualBox default)
  $adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue

  if ($adapter) {
    Write-Host "[OK] Found adapter by name: Ethernet"
  } else {
    # Method 5: Look for any non-NAT adapter (exclude 10.0.2.x)
    $natIp = Get-NetIPAddress -IPAddress 10.0.2.* -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($natIp) {
      $natAdapter = Get-NetAdapter -InterfaceIndex $natIp.InterfaceIndex -ErrorAction SilentlyContinue
      Write-Host "[INFO] NAT adapter: $($natAdapter.Name) (10.0.2.x)"

      # Get all adapters except the NAT one
      $allAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
                     Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike "*Loopback*" }
      $adapter = $allAdapters | Where-Object { $_.Name -ne $natAdapter.Name } | Select-Object -First 1

      if ($adapter) {
        Write-Host "[OK] Found non-NAT adapter: $($adapter.Name)"
      }
    }
  }
}

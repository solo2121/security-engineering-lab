# Method 3: Look for adapter named "Ethernet 1" (most common for libvirt)
$adapter = Get-NetAdapter -Name "Ethernet 1" -ErrorAction SilentlyContinue

if ($adapter) {
  Write-Host "[OK] Found adapter by name: Ethernet 1"
} else {
  # Method 4: Look for any adapter that's NOT the NAT one (exclude 192.168.121.x)
  $natIp = Get-NetIPAddress -IPAddress 192.168.121.* -ErrorAction SilentlyContinue |
           Select-Object -First 1
  if ($natIp) {
    $natAdapter = Get-NetAdapter -InterfaceIndex $natIp.InterfaceIndex -ErrorAction SilentlyContinue
    Write-Host "[INFO] NAT adapter: $($natAdapter.Name) (192.168.121.x)"

    # Get all adapters except the NAT one
    $allAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
                   Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike "*Loopback*" }
    $adapter = $allAdapters | Where-Object { $_.Name -ne $natAdapter.Name } | Select-Object -First 1

    if ($adapter) {
      Write-Host "[OK] Found non-NAT adapter: $($adapter.Name)"
    }
  }
}

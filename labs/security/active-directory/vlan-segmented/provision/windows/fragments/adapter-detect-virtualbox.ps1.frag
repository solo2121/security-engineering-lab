# Method 3: Ethernet 2 (VirtualBox internal network)
if (-not $adapter) {
  $adapter = Get-NetAdapter -Name "Ethernet 2" -ErrorAction SilentlyContinue
  if ($adapter) { Write-Log "Found adapter by name: Ethernet 2" }
}

# Method 4: Ethernet (VirtualBox NAT)
if (-not $adapter) {
  $adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
  if ($adapter) { Write-Log "Found adapter by name: Ethernet" }
}

# Method 5: Any non-NAT adapter
if (-not $adapter) {
  $natIp = Get-NetIPAddress -IPAddress 10.0.2.* -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($natIp) {
    $natAdapter = Get-NetAdapter -InterfaceIndex $natIp.InterfaceIndex -ErrorAction SilentlyContinue
    Write-Log "NAT adapter: $($natAdapter.Name) (10.0.2.x)"
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
               Where-Object { $_.Status -eq 'Up' -and $_.Name -ne $natAdapter.Name -and $_.Name -notlike "*Loopback*" } |
               Select-Object -First 1
    if ($adapter) { Write-Log "Found non-NAT adapter: $($adapter.Name)" }
  }
}

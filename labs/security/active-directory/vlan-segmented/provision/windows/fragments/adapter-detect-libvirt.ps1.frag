# Method 3: Ethernet 1
$adapter = Get-NetAdapter -Name "Ethernet 1" -ErrorAction SilentlyContinue
if ($adapter) { Write-Log "Found adapter by name: Ethernet 1" }

# Method 4: Any non-NAT adapter
if (-not $adapter) {
  $natIp = Get-NetIPAddress -IPAddress 192.168.121.* -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($natIp) {
    $natAdapter = Get-NetAdapter -InterfaceIndex $natIp.InterfaceIndex -ErrorAction SilentlyContinue
    Write-Log "NAT/management adapter: $($natAdapter.Name) (192.168.121.x)"
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
               Where-Object { $_.Status -eq 'Up' -and $_.Name -ne $natAdapter.Name -and $_.Name -notlike "*Loopback*" } |
               Select-Object -First 1
    if ($adapter) { Write-Log "Found non-NAT adapter: $($adapter.Name)" }
  }
}

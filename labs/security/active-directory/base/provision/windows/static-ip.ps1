Write-Host "=============================================="
Write-Host "FIXED STATIC IP CONFIGURATION: @@IP@@"
Write-Host "=============================================="

# Wait for network to fully initialize
Write-Host "[*] Waiting 60 seconds for network initialization..."
Start-Sleep -Seconds 60

# ------------------------------------------------------------
# CRITICAL FIX: Find the correct adapter (not the APIPA one)
# ------------------------------------------------------------
Write-Host "[*] Searching for correct network adapter..."

# Method 1: Look for adapter with our target IP (if already assigned)
$adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -eq '@@IP@@' } |
           ForEach-Object { Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue }

if ($adapter) {
  Write-Host "[OK] Found adapter with target IP: $($adapter.Name)"
} else {
  # Method 2: Look for adapter with 172.28.128.x network (our lab subnet)
  $adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -like '172.28.128.*' } |
             ForEach-Object { Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue } |
             Select-Object -First 1

  if ($adapter) {
    Write-Host "[OK] Found adapter on lab subnet: $($adapter.Name)"
  } else {
    @@ADAPTER_DETECT@@
  }
}

# Last resort - show all adapters for debugging
if (-not $adapter) {
  Write-Host "[WARNING] Could not find correct adapter, showing all adapters for debugging:"
  Write-Host "=== ALL NETWORK ADAPTERS ==="
  Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed
  Write-Host "=== ALL IP ADDRESSES ==="
  Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength

  # Try to pick the first non-loopback, up adapter
  $adapter = Get-NetAdapter |
             Where-Object {$_.Status -eq 'Up' -and $_.Name -notlike "*Loopback*"} |
             Select-Object -First 1
  Write-Host "[WARNING] Using first available adapter: $($adapter.Name)"
}

if (-not $adapter) {
  Write-Host "[ERROR] No suitable network adapter found"
  exit 1
}

$ifIndex = $adapter.ifIndex
Write-Host "[OK] Using adapter: $($adapter.Name) (Index: $ifIndex)"

# ------------------------------------------------------------
# ORIGINAL FUNCTIONALITY PRESERVED EXACTLY FROM HERE ON
# ------------------------------------------------------------

# Remove any existing IP configuration
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# CRITICAL FIX 1: Disable Duplicate Address Detection
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -DadTransmits 0 -ErrorAction SilentlyContinue
Write-Host "[OK] Disabled Duplicate Address Detection"

# CRITICAL FIX 2: Set static IP with SkipAsSource = false
New-NetIPAddress `
  -InterfaceIndex $adapter.ifIndex `
  -IPAddress @@IP@@ `
  -PrefixLength 24 `
  -SkipAsSource $false `
  -ErrorAction SilentlyContinue

Write-Host "[OK] Set static IP: @@IP@@"

# CRITICAL FIX 3: Add dummy gateway to make network "Preferred"
New-NetRoute `
  -InterfaceIndex $adapter.ifIndex `
  -DestinationPrefix "0.0.0.0/0" `
  -NextHop 172.28.128.1 `
  -ErrorAction SilentlyContinue
Write-Host "[OK] Added dummy gateway to stabilize network"

# Set DNS to DC01
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @@DC_IP@@
Write-Host "[OK] Set DNS to DC01 (@@DC_IP@@)"

# Set network to Private (silent failure if domain-joined - this is normal)
try {
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
} catch {
    # Network category is likely DomainAuthenticated - this is normal for domain-joined VMs
    Write-Host "[INFO] Network category already set (domain-joined)"
}

# Verify configuration
$ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
Write-Host "[OK] IP configured: $($ipConfig.IPAddress)"
Write-Host "[OK] Address State: $($ipConfig.AddressState)"

# Disable Windows Firewall for lab
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
Write-Host "[OK] Windows Firewall disabled"

# Ensure WinRM is running
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Final verification
Write-Host "=============================================="
Write-Host "IP CONFIGURATION VERIFICATION"
Write-Host "=============================================="
ipconfig /all
Write-Host "=============================================="

Write-Host "=============================================="
Write-Host "STATIC IP CONFIGURATION COMPLETE"
Write-Host "=============================================="

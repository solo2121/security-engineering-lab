$LogDir = "C:\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
$LogFile = "$LogDir\static-ip.log"

function Write-Log {
  param($Message)
  $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "$Timestamp - $Message"
  Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

Write-Log "Configuring static IP: @@IP@@ (gateway: @@GATEWAY@@)"

Write-Log "Waiting 60 seconds for network initialization..."
Start-Sleep -Seconds 60

Write-Log "Searching for correct network adapter..."
$adapter = $null

# Method 1: Target IP
$adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -eq '@@IP@@' } |
           ForEach-Object { Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue }

# Method 2: Lab subnet
if (-not $adapter) {
  $adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -like '172.28.*' } |
             ForEach-Object { Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue } |
             Select-Object -First 1
  if ($adapter) { Write-Log "Found adapter on lab subnet: $($adapter.Name)" }
}

@@ADAPTER_DETECT@@

# Method 6: Last resort
if (-not $adapter) {
  $adapter = Get-NetAdapter |
             Where-Object {$_.Status -eq 'Up' -and $_.Name -notlike "*Loopback*"} |
             Select-Object -First 1
  if ($adapter) { Write-Log "WARNING: Using first available adapter: $($adapter.Name)" }
}

if (-not $adapter) {
  Write-Log "ERROR: No suitable network adapter found"
  exit 1
}

Write-Log "Using adapter: $($adapter.Name) (Index: $($adapter.ifIndex))"

# Remove existing configuration
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# Disable Duplicate Address Detection
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -DadTransmits 0 -ErrorAction SilentlyContinue
Write-Log "Disabled Duplicate Address Detection"

# Set static IP with SkipAsSource=$false
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress @@IP@@ -PrefixLength 24 -SkipAsSource $false -ErrorAction SilentlyContinue
Write-Log "Set static IP: @@IP@@"

# Add real VLAN gateway (OPNsense)
New-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop @@GATEWAY@@ -ErrorAction SilentlyContinue
Write-Log "Added gateway: @@GATEWAY@@"

# Set DNS
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @@DC_IP@@
Write-Log "Set DNS to DC01 (@@DC_IP@@)"

# Set network to Private
try {
  Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
} catch {
  Write-Log "Network category already set (domain-joined)"
}

# Disable firewall
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
Write-Log "Windows Firewall disabled"

# Ensure WinRM
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

Write-Log "STATIC IP CONFIGURATION COMPLETE"

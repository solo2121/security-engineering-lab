$ErrorActionPreference = 'Continue'
Write-Host "@@HOSTNAME_UPPER@@ DOMAIN JOIN"
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1
if ($adapter) {
  Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '@@DC_IP@@'
}
$sec = ConvertTo-SecureString '@@DOMAIN_JOIN_PASS_SQ@@' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('@@DOMAIN_NETBIOS@@\@@DOMAIN_JOIN_USER@@', $sec)
Add-Computer -DomainName "@@DOMAIN_NAME@@" -Credential $cred -Force
Rename-Computer -NewName '@@HOSTNAME@@' -Force
shutdown /r /t 5 /f

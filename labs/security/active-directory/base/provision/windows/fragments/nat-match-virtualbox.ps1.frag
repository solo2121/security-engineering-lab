$_.Name -like "*eth0*" -or
$_.Name -like "*NAT*" -or
$_.Name -like "*VirtualBox Host-Only*" -or
(Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue |
 Where-Object { $_.IPAddress -like "10.0.2.*" })

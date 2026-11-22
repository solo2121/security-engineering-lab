$_.Name -like "*eth0*" -or
$_.InterfaceDescription -like "*virtio*" -or
(Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue |
 Where-Object { $_.IPAddress -like "192.168.121.*" })

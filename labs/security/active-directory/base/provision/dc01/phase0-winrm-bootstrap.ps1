Write-Host 'PHASE 0: WINRM BOOTSTRAP'
Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service WinRM -ErrorAction SilentlyContinue
winrm set winrm/config/service '@{AllowUnencrypted="true"}' 2>$null
winrm set winrm/config/service/auth '@{Basic="true"}' 2>$null
winrm set winrm/config/listener?Address=*+Transport=HTTP 2>$null
netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes 2>$null
Write-Host '[OK] WinRM bootstrap complete'

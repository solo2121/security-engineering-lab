$LogDir = "C:\\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
Write-Host "Configuring WIN10"
net user localadmin P@ssw0rd! /add
net localgroup administrators localadmin /add
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos" /v "EnableKeyTrust" /t REG_DWORD /d 1 /f 2>$null
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "UseLogonCredential" /t REG_DWORD /d 1 /f 2>$null
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" /v "UseLogonCredential" /t REG_DWORD /d 1 /f 2>$null
schtasks /create /tn "VulnerableTask" /tr "cmd /c whoami" /sc daily /ru SYSTEM /f 2>$null

"WIN10 configured" | Out-File C:\\WIN10-COMPLETE.txt -Force

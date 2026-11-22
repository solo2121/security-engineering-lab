Write-Host "PRINT NIGHTMARE CONFIGURATION"
Install-WindowsFeature Print-Services
New-Item -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Printers\\PointAndPrint" -Force -ErrorAction SilentlyContinue
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" /v RestrictDriverInstallationToAdministrators /t REG_DWORD /d 0 /f

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print" /v "RpcAuthnLevelPrivacyEnabled" /t REG_DWORD /d 0 /f 2>$null
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print" /v "AllowInsecureGuestAuth" /t REG_DWORD /d 1 /f 2>$null
reg add "HKLM\Software\Policies\Microsoft\Windows NT\Printers" /v "RegisterSpoolerRemoteRpcEndPoint" /t REG_DWORD /d 2 /f 2>$null

Add-PrinterDriver -Name "Microsoft Print To PDF" -ErrorAction SilentlyContinue
Add-Printer -Name "VulnerablePrinter" -DriverName "Microsoft Print To PDF" -Shared -Published -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Printer Sharing SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow
net localgroup administrators "DOMAIN\Domain Users" /add 2>$null

"PRINT01 configured" | Out-File C:\\PRINT01-COMPLETE.txt -Force

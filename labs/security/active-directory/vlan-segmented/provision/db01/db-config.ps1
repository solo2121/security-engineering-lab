$LogDir = "C:\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
Write-Host "Configuring DB01"
Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow
"DB01 configured" | Out-File C:\DB01-COMPLETE.txt -Force

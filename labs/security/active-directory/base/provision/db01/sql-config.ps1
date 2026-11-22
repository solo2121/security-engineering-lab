Write-Host "SQL SERVER CONFIGURATION"
Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow
"DB01 configured" | Out-File C:\DB01-COMPLETE.txt -Force

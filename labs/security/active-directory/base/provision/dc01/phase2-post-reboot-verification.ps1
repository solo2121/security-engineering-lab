if (Test-Path 'C:\DC-FINAL.txt') { exit 0 }
if (-not (Test-Path 'C:\PHASE1-COMPLETE.txt')) { exit 1 }
Write-Host 'PHASE 2: POST-REBOOT VERIFICATION'
Start-Sleep -Seconds 30
Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service WinRM -ErrorAction SilentlyContinue
winrm quickconfig -quiet -force 2>$null
winrm set winrm/config/service '@{AllowUnencrypted="true"}' 2>$null
winrm set winrm/config/service/auth '@{Basic="true";Kerberos="true";Negotiate="true"}' 2>$null
"Phase 2 completed" | Out-File C:\PHASE2-COMPLETE.txt -Force
Write-Host '[SUCCESS] Phase 2 complete'

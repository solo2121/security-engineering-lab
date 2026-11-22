if (Test-Path 'C:\DC-FINAL.txt') { exit 0 }
Write-Host 'PHASE 1: BASIC SETUP'
net user vagrant /active:yes 2>$null
net localgroup administrators vagrant /add 2>$null
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private 2>$null
Install-WindowsFeature AD-Domain-Services, RSAT-AD-PowerShell, RSAT-ADDS -IncludeManagementTools 2>$null
"Phase 1 completed" | Out-File C:\PHASE1-COMPLETE.txt -Force
Write-Host '[SUCCESS] Phase 1 complete!'

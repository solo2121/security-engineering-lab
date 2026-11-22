Write-Host "PHASE 6: CLEANUP"
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
"Cleanup completed" | Out-File C:\CLEANUP-COMPLETE.txt -Force

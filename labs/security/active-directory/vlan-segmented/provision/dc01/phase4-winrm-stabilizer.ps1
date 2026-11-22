Write-Host "Stabilizing WinRM..."
Start-Sleep -Seconds 60
Set-Service WinRM -StartupType Automatic
Start-Service WinRM

Write-Host "Stabilizing WinRM after AD promotion..."
Start-Sleep -Seconds 60
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Write-Host "[OK] WinRM stabilized after AD promotion"

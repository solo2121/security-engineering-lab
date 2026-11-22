Write-Host "=============================================="
Write-Host "WINDOWS DEFENDER LAB BASELINE"
Write-Host "=============================================="

Write-Host "[*] Configuring Defender via registry..."

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Force -ErrorAction SilentlyContinue | Out-Null

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "[OK] Registry keys configured"

Write-Host "[*] Stopping Defender service..."
Stop-Service WinDefend -Force -ErrorAction SilentlyContinue

Write-Host "=============================================="
Write-Host "BASELINE CONFIGURATION COMPLETE"
Write-Host "=============================================="

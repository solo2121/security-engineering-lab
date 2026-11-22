$LogDir = "C:\LabLogs"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
$LogFile = "$LogDir\disable-defender.log"

function Write-Log {
  param($Message)
  $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "$Timestamp - $Message"
  Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

Write-Log "Configuring Windows Defender"

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Force -ErrorAction SilentlyContinue | Out-Null

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue

Stop-Service WinDefend -Force -ErrorAction SilentlyContinue
Write-Log "Windows Defender disabled"

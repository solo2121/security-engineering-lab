if (Test-Path 'C:\DC-FINAL.txt') { exit 0 }
if (-not (Test-Path 'C:\PHASE2-COMPLETE.txt')) { exit 1 }
Write-Host 'PHASE 3: AD PROMOTION (this will take a few minutes...)'
Import-Module ADDSDeployment -ErrorAction SilentlyContinue
if (-not (Get-Module ADDSDeployment)) {
  Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
  Import-Module ADDSDeployment
}
$safeModePass = ConvertTo-SecureString 'Passw0rd!' -AsPlainText -Force
try {
  Install-ADDSForest `
    -DomainName "@@DOMAIN_NAME@@" `
    -DomainNetbiosName "@@DOMAIN_NETBIOS@@" `
    -InstallDNS `
    -SafeModeAdministratorPassword $safeModePass `
    -Force `
    -NoRebootOnCompletion `
    -WarningAction SilentlyContinue `
    -ErrorAction Stop
  Write-Host '[SUCCESS] AD promotion complete!'
} catch {
  Write-Error "AD promotion failed: $_"
  exit 1
}
"AD promoted" | Out-File C:\AD-PROMOTED.txt -Force
Write-Host 'Rebooting in 10 seconds...'
shutdown /r /t 10 /f

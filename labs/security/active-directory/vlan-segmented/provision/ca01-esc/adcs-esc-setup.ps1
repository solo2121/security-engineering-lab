  $LogDir = "C:\LabLogs"
  New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
  $LogFile = "$LogDir\ca-esc-setup.log"

  function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$Timestamp - $Message"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
  }

  Write-Log "Setting up AD CS ESC vulnerabilities"

  Install-WindowsFeature AD-Certificate -IncludeManagementTools
  Install-AdcsCertificationAuthority -CAType EnterpriseRootCa -CACommonName "LAB-ESC-CA" -Force

  certutil -setreg policy\EditFlags +EDITF_ATTRIBUTESUBJECTALTNAME2

  Install-WindowsFeature ADCS-Web-Enrollment -IncludeManagementTools
  Install-AdcsWebEnrollment -Force

  New-NetFirewallRule -DisplayName "HTTP Web Enrollment" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow

  Restart-Service certsvc -Force

  Import-Module ActiveDirectory
  $domainDN = "@@DOMAIN_DN@@"
  $configNC = (Get-ADRootDSE).configurationNamingContext
  $templatesPath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"

  Write-Log "Creating ESC1-Template"
  $templateLdif = @"
dn: CN=ESC1-Template,$templatesPath
objectClass: pKICertificateTemplate
cn: ESC1-Template
displayName: ESC1 Vulnerable Template
pKIDefaultKeySpec: 1
pKIKeySpec: 1
pKIKeyUsage: 0xa0
pKICriticalExtensions: 2.5.29.15
pKIExtendedKeyUsage: 1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.4
msPKI-Certificate-Name-Flag: 1
msPKI-Enrollment-Flag: 2
msPKI-Private-Key-Flag: 16
msPKI-Template-Minor-Revision: 1
msPKI-Template-Schema-Version: 1
msPKI-RA-Signature: 0
msPKI-Cert-Template-OID: 1.3.6.1.4.1.311.21.8.12345678.1.1.1
msPKI-Certificate-Policy: 1.3.6.1.4.1.311.21.8.12345678.1.1.1
"@

  $templateLdif | Out-File C:ESC1-Template.ldf -Force
  ldifde -i -f C:ESC1-Template.ldf 2>$null

  $templateDN = "CN=ESC1-Template,$templatesPath"
  $guid = New-Object Guid "0e10c968-78fb-11d2-90d4-00c04f79dc55"

  try {
    $acl = Get-Acl "AD:\$templateDN"
    $identity = [System.Security.Principal.NTAccount]"@@DOMAIN_NETBIOS@@\Domain Users"
    $rights = [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight"
    $type = [System.Security.AccessControl.AccessControlType]"Allow"
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, $rights, $type, $guid)
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$templateDN" $acl
    Write-Log "ESC1 template configured"
  } catch {
    Write-Log "WARN: ESC1 ACL setup failed: $_"
  }

  Write-Log "Creating ESC3 Enrollment Agent template"
  $esc3Ldif = @"
dn: CN=ESC3-EnrollmentAgent,$templatesPath
objectClass: pKICertificateTemplate
cn: ESC3-EnrollmentAgent
displayName: ESC3 Enrollment Agent
pKIDefaultKeySpec: 2
pKIKeySpec: 2
pKIExtendedKeyUsage: 1.3.6.1.4.1.311.20.2.1
msPKI-Certificate-Name-Flag: 0
msPKI-Enrollment-Flag: 0
msPKI-Private-Key-Flag: 0
msPKI-Template-Minor-Revision: 1
msPKI-Template-Schema-Version: 1
"@

  $esc3Ldif | Out-File C:ESC3-Template.ldf -Force
  ldifde -i -f C:ESC3-Template.ldf 2>$null

  Write-Log "Setting ESC4 permissions"
  try {
    $acl = Get-Acl "AD:\$templateDN"
    $identity = [System.Security.Principal.NTAccount]"@@DOMAIN_NETBIOS@@\Domain Users"
    $rights = [System.DirectoryServices.ActiveDirectoryRights]"WriteProperty"
    $type = [System.Security.AccessControl.AccessControlType]"Allow"
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, $rights, $type)
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$templateDN" $acl
    Write-Log "ESC4 permissions granted"
  } catch {
    Write-Log "WARN: ESC4 setup failed: $_"
  }

  Write-Log "Creating ESC7 CA admin group"
  New-ADGroup -Name "CA_Admins_ESC7" -GroupCategory Security -GroupScope Global -Path "OU=Groups,$domainDN"
  Add-ADGroupMember -Identity "CA_Admins_ESC7" -Members "Domain Users"

  $caPath = "CN=LAB-ESC-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,$configNC"
  try {
    $acl = Get-Acl "AD:\$caPath"
    $identity = [System.Security.Principal.NTAccount]"@@DOMAIN_NETBIOS@@\CA_Admins_ESC7"
    $rights = [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight"
    $type = [System.Security.AccessControl.AccessControlType]"Allow"
    $guid = New-Object Guid "a05b8cc1-17b4-44cc-a680-0f36ae5c10e8"
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, $rights, $type, $guid)
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$caPath" $acl
    Write-Log "ESC7 permissions granted"
  } catch {
    Write-Log "WARN: ESC7 setup failed: $_"
  }

  Restart-Service certsvc -Force

  Add-DnsServerResourceRecordA -Name "CA01-ESC" -ZoneName "@@DOMAIN_NAME@@" -IPv4Address "@@VM_IP@@" -ErrorAction SilentlyContinue

  Write-Log "ESC VULNERABILITIES CONFIGURED SUCCESSFULLY"
  "CA01-ESC fully configured with ESC vulns" | Out-File C:\CA01-ESC-COMPLETE.txt -Force

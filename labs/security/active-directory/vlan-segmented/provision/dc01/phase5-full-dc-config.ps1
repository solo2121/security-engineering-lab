  $ErrorActionPreference = 'Continue'
  $LogDir = "C:\\LabLogs"
  New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue
  $LogFile = "$LogDir\\dc-full-config.log"

  function Log {
    param($msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $msg"
    Add-Content -Path $LogFile -Value "$timestamp - $msg"
  }

  if (Test-Path "C:\\DC-FINAL.txt") {
    Log "DC already fully configured. Skipping Phase 5."
    exit 0
  }
  if (-not (Test-Path "C:\\AD-PROMOTED.txt")) {
    Log "AD promotion not detected. Exiting full DC configuration."
    exit 0
  }

  Log "PHASE 5: COMPLETE DC CONFIGURATION WITH 45+ REALISTIC USERS"
  Start-Sleep -Seconds 60

  Import-Module ActiveDirectory -ErrorAction Stop

  $domainName = "lab.local"
  $domainParts = $domainName.Split('.')
  $domainDN = ($domainParts | ForEach-Object { "DC=$_" }) -join ','

  $attempt = 0
  while ($attempt -lt 30) {
    $attempt++
    try { Get-ADDomain -ErrorAction Stop; Log "AD Domain detected"; break }
    catch { Log "Waiting for AD... attempt $attempt/30"; Start-Sleep -Seconds 30 }
  }

  Log "DISABLING PASSWORD COMPLEXITY POLICY"
  Set-ADDefaultDomainPasswordPolicy -Identity $domainName -ComplexityEnabled $false -MinPasswordLength 0 -MaxPasswordAge 365.00:00:00 -MinPasswordAge 0.00:00:00 -LockoutThreshold 0 -ErrorAction Stop
  gpupdate /force 2>$null
  Start-Sleep -Seconds 15

  $labOU = "OU=LAB,$domainDN"
  New-ADOrganizationalUnit -Name "LAB" -Path $domainDN -ErrorAction SilentlyContinue

  $ous = @{
    "Users" = @("Admins","IT","HR","Finance","Security","Sales","Marketing","Executives","R&D","Engineering","Legal","Compliance","Operations","Temp-Contractors","Vendors")
    "Groups" = @("Security","Distribution","Role-Based","Dynamic","Mail-Enabled")
    "Computers" = @("Workstations","Servers","Virtual-Machines","DMZ","Test-Dev")
    "ServiceAccounts" = @("Managed","Legacy","Scheduled-Tasks","Application-Pools","GMSA","SQL")
    "Delegated" = @("Helpdesk","Admins","Auditors")
    "Resources" = @("FileShares","Printers","Applications")
    "PrivilegedAccess" = @("PAW","AdminWorkstations","BreakGlass")
    "Servers" = @("DomainControllers","SQL","Web","Application","Database","Certificate")
  }

  foreach ($parent in $ous.Keys) {
    New-ADOrganizationalUnit -Name $parent -Path $labOU -ErrorAction SilentlyContinue
    foreach ($child in $ous[$parent]) {
      New-ADOrganizationalUnit -Name $child -Path "OU=$parent,$labOU" -ErrorAction SilentlyContinue
    }
  }

  $groups = @(
    @{Name="SG_Domain_Admins"; Description="Domain Administrators"; OU="Security"},
    @{Name="SG_Enterprise_Admins"; Description="Enterprise Administrators"; OU="Security"},
    @{Name="SG_IT_Admins"; Description="IT Administrators"; OU="Security"},
    @{Name="SG_Security_Admins"; Description="Security Administrators"; OU="Security"},
    @{Name="SG_Helpdesk_Tier1"; Description="Helpdesk Tier 1 Support"; OU="Role-Based"},
    @{Name="SG_Helpdesk_Tier2"; Description="Helpdesk Tier 2 Support"; OU="Role-Based"},
    @{Name="SG_Certificate_Managers"; Description="Certificate Template Managers"; OU="Security"},
    @{Name="SG_GPO_Editors"; Description="GPO Editors"; OU="Security"},
    @{Name="SG_Server_Operators"; Description="Server Operators"; OU="Role-Based"},
    @{Name="SG_Backup_Operators"; Description="Backup Operators"; OU="Role-Based"},
    @{Name="SG_DNS_Admins"; Description="DNS Administrators"; OU="Security"},
    @{Name="SG_SQL_Admins"; Description="SQL Server Administrators"; OU="Security"},
    @{Name="SG_Print_Operators"; Description="Print Server Operators"; OU="Role-Based"}
  )

  foreach ($g in $groups) {
    New-ADGroup -Name $g.Name -GroupCategory Security -GroupScope Global -Description $g.Description -Path "OU=$($g.OU),OU=Groups,$labOU" -ErrorAction SilentlyContinue
  }

  Add-ADGroupMember -Identity "SG_Enterprise_Admins" -Members "SG_Domain_Admins" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity "SG_IT_Admins" -Members "SG_Security_Admins" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity "Domain Admins" -Members "SG_IT_Admins" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity "SG_Certificate_Managers" -Members "SG_IT_Admins" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity "SG_GPO_Editors" -Members "SG_Helpdesk_Tier1" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity "SG_SQL_Admins" -Members "SG_IT_Admins" -ErrorAction SilentlyContinue

  $departmentGroups = @(
    @{Name="IT_Users"; OU="IT"}, @{Name="HR_Users"; OU="HR"}, @{Name="Finance_Users"; OU="Finance"},
    @{Name="Security_Users"; OU="Security"}, @{Name="Sales_Users"; OU="Sales"}, @{Name="Marketing_Users"; OU="Marketing"},
    @{Name="Executive_Users"; OU="Executives"}, @{Name="RND_Users"; OU="R&D"}, @{Name="Engineering_Users"; OU="Engineering"},
    @{Name="Legal_Users"; OU="Legal"}, @{Name="Compliance_Users"; OU="Compliance"}, @{Name="Operations_Users"; OU="Operations"},
    @{Name="Temp_Contractors"; OU="Temp-Contractors"}, @{Name="Vendor_Users"; OU="Vendors"}
  )

  foreach ($dept in $departmentGroups) {
    New-ADGroup -Name $dept.Name -GroupCategory Security -GroupScope Global -Path "OU=$($dept.OU),OU=Users,$labOU" -ErrorAction SilentlyContinue
  }

  New-ADGroup -Name "Service_Desk" -GroupCategory Security -GroupScope Global -Path "OU=IT,OU=Users,$labOU" -ErrorAction SilentlyContinue

  $functionalGroups = @(
    "VPN_Users", "Remote_Desktop_Users", "Privileged_Access_Workstation_Users",
    "Server_Admins", "Backup_Operators", "DBA_Group", "Helpdesk_Managers", "Patch_Management",
    "Asset_Management", "Incident_Response", "Threat_Hunting", "Cloud_Admins", "DevOps_Team",
    "Data_Science", "Print_Users", "Fax_Users", "Email_Users", "File_Share_Users"
  )

  foreach ($fg in $functionalGroups) {
    New-ADGroup -Name $fg -GroupCategory Security -GroupScope Global -Path "OU=Role-Based,OU=Groups,$labOU" -ErrorAction SilentlyContinue
  }

  $labAdmin = "labadmin"
  $labAdminPass = ConvertTo-SecureString "LabAdmin123!" -AsPlainText -Force
  if (-not (Get-ADUser -Filter "SamAccountName -eq '$labAdmin'" -ErrorAction SilentlyContinue)) {
    New-ADUser -Name $labAdmin -SamAccountName $labAdmin -AccountPassword $labAdminPass -Enabled $true -Path "OU=Admins,OU=Users,$labOU" -UserPrincipalName "$labAdmin@$domainName" -PasswordNeverExpires $true
    Add-ADGroupMember -Identity "SG_Domain_Admins" -Members $labAdmin
    Add-ADGroupMember -Identity "SG_IT_Admins" -Members $labAdmin
    Add-ADGroupMember -Identity "SG_Certificate_Managers" -Members $labAdmin
    Add-ADGroupMember -Identity "SG_Enterprise_Admins" -Members $labAdmin
    Add-ADGroupMember -Identity "SG_SQL_Admins" -Members $labAdmin
    Log "Created labadmin"
  }

  $executives = @(
    @{Name="sarah.ceo"; Pass="CeoPass2024!"; Dept="Executives"; Title="CEO"; Groups=@("Executive_Users","VPN_Users")},
    @{Name="michael.cfo"; Pass="CfoPass2024!"; Dept="Executives"; Title="CFO"; Groups=@("Executive_Users","Finance_Users","VPN_Users"); Manager="sarah.ceo"},
    @{Name="jennifer.cto"; Pass="CtoPass2024!"; Dept="Executives"; Title="CTO"; Groups=@("Executive_Users","Engineering_Users","Cloud_Admins"); Manager="sarah.ceo"},
    @{Name="robert.cio"; Pass="CioPass2024!"; Dept="Executives"; Title="CIO"; Groups=@("Executive_Users","IT_Users","Server_Admins","Cloud_Admins"); Manager="sarah.ceo"},
    @{Name="patricia.coo"; Pass="CooPass2024!"; Dept="Executives"; Title="COO"; Groups=@("Executive_Users","Operations_Users"); Manager="sarah.ceo"},
    @{Name="james.ciso"; Pass="CisoPass2024!"; Dept="Executives"; Title="CISO"; Groups=@("Executive_Users","Security_Users","Incident_Response"); Manager="sarah.ceo"}
  )

  Log "Creating Executive users first..."
  foreach ($u in $executives) {
    $userPass = ConvertTo-SecureString $u.Pass -AsPlainText -Force
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Name)'" -ErrorAction SilentlyContinue)) {
      $firstName = ($u.Name.Split('.')[0]).Substring(0,1).ToUpper() + ($u.Name.Split('.')[0]).Substring(1)
      $lastName = ($u.Name.Split('.')[1]).Substring(0,1).ToUpper() + ($u.Name.Split('.')[1]).Substring(1)
      try {
        New-ADUser -Name $u.Name -SamAccountName $u.Name -UserPrincipalName "$($u.Name)@$domainName" -GivenName $firstName -Surname $lastName -DisplayName "$firstName $lastName" -Title $u.Title -Department $u.Dept -AccountPassword $userPass -Enabled $true -Path "OU=$($u.Dept),OU=Users,$labOU" -PasswordNeverExpires $true -ErrorAction Stop
        Log "Created executive: $($u.Name)"
      } catch {
        Log "WARNING: Could not create executive $($u.Name): $_"
      }
    }
  }

  Log "Waiting 60 seconds for executives to replicate..."
  Start-Sleep -Seconds 60

  $restOfUsers = @(
    @{Name="john.doe"; Pass="Password123!"; Dept="IT"; Title="Helpdesk Tier 1"; Groups=@("IT_Users","Service_Desk","SG_Helpdesk_Tier1","VPN_Users"); Manager="robert.cio"},
    @{Name="jane.smith"; Pass="Spring2024!"; Dept="IT"; Title="Helpdesk Tier 2"; Groups=@("IT_Users","Service_Desk","SG_Helpdesk_Tier2","Remote_Desktop_Users"); Manager="robert.cio"},
    @{Name="bob.wilson"; Pass="CertP@ss456!"; Dept="IT"; Title="Certificate Manager"; Groups=@("IT_Users","SG_Certificate_Managers","Server_Admins"); Manager="robert.cio"},
    @{Name="alice.brown"; Pass="GPOP@ss789!"; Dept="Security"; Title="Security Analyst"; Groups=@("Security_Users","SG_GPO_Editors","Incident_Response"); Manager="james.ciso"},
    @{Name="david.miller"; Pass="ITP@ss321!"; Dept="IT"; Title="Sysadmin"; Groups=@("IT_Users","Server_Admins","Patch_Management"); Manager="robert.cio"},
    @{Name="lisa.davis"; Pass="LisaPass123!"; Dept="IT"; Title="Network Admin"; Groups=@("IT_Users","Server_Admins","SG_DNS_Admins"); Manager="robert.cio"},
    @{Name="kevin.williams"; Pass="KevinPass123!"; Dept="IT"; Title="Security Specialist"; Groups=@("IT_Users","Security_Users","Threat_Hunting"); Manager="james.ciso"},
    @{Name="nancy.moore"; Pass="NancyPass123!"; Dept="IT"; Title="DBA"; Groups=@("IT_Users","DBA_Group","Server_Admins","SG_SQL_Admins"); Manager="robert.cio"},
    @{Name="paul.taylor"; Pass="PaulPass123!"; Dept="IT"; Title="Cloud Admin"; Groups=@("IT_Users","Cloud_Admins","Server_Admins"); Manager="robert.cio"},
    @{Name="lisa.anderson"; Pass="SecP@ss789!"; Dept="Security"; Title="Security Engineer"; Groups=@("Security_Users","SG_Certificate_Managers","Incident_Response"); Manager="james.ciso"},
    @{Name="thomas.clark"; Pass="TomPass123!"; Dept="Security"; Title="SOC Analyst"; Groups=@("Security_Users","Incident_Response"); Manager="james.ciso"},
    @{Name="michelle.wright"; Pass="MichellePass123!"; Dept="Security"; Title="Incident Responder"; Groups=@("Security_Users","Incident_Response","Threat_Hunting"); Manager="james.ciso"},
    @{Name="sarah.johnson"; Pass="HRP@ss123!"; Dept="HR"; Title="HR Manager"; Groups=@("HR_Users","VPN_Users"); Manager="sarah.ceo"},
    @{Name="james.brown"; Pass="JamesPass123!"; Dept="HR"; Title="HR Generalist"; Groups=@("HR_Users"); Manager="sarah.johnson"},
    @{Name="emily.davis"; Pass="EmilyPass123!"; Dept="HR"; Title="Recruiter"; Groups=@("HR_Users"); Manager="sarah.johnson"},
    @{Name="mike.taylor"; Pass="FinP@ss456!"; Dept="Finance"; Title="Finance Manager"; Groups=@("Finance_Users","VPN_Users"); Manager="michael.cfo"},
    @{Name="laura.martin"; Pass="LauraPass123!"; Dept="Finance"; Title="Accountant"; Groups=@("Finance_Users"); Manager="mike.taylor"},
    @{Name="robert.jackson"; Pass="RobertPass123!"; Dept="Finance"; Title="Financial Analyst"; Groups=@("Finance_Users"); Manager="mike.taylor"},
    @{Name="chris.evans"; Pass="SalesPass123!"; Dept="Sales"; Title="Sales Director"; Groups=@("Sales_Users","VPN_Users"); Manager="sarah.ceo"},
    @{Name="amanda.white"; Pass="AmandaPass123!"; Dept="Sales"; Title="Account Exec"; Groups=@("Sales_Users"); Manager="chris.evans"},
    @{Name="brian.harris"; Pass="BrianPass123!"; Dept="Sales"; Title="Sales Rep"; Groups=@("Sales_Users"); Manager="chris.evans"},
    @{Name="diana.prince"; Pass="MarketingPass123!"; Dept="Marketing"; Title="Marketing Director"; Groups=@("Marketing_Users"); Manager="sarah.ceo"},
    @{Name="peter.parker"; Pass="PeterPass123!"; Dept="Marketing"; Title="Marketing Specialist"; Groups=@("Marketing_Users"); Manager="diana.prince"},
    @{Name="tony.stark"; Pass="StarkPass123!"; Dept="R&D"; Title="R&D Director"; Groups=@("RND_Users","Data_Science"); Manager="jennifer.cto"},
    @{Name="bruce.banner"; Pass="BannerPass123!"; Dept="R&D"; Title="Research Scientist"; Groups=@("RND_Users","Data_Science"); Manager="tony.stark"},
    @{Name="steve.rogers"; Pass="StevePass123!"; Dept="Engineering"; Title="Engineering Manager"; Groups=@("Engineering_Users","DevOps_Team"); Manager="jennifer.cto"},
    @{Name="wanda.maximoff"; Pass="WandaPass123!"; Dept="Engineering"; Title="DevOps Engineer"; Groups=@("Engineering_Users","DevOps_Team","Cloud_Admins"); Manager="steve.rogers"},
    @{Name="natasha.romanoff"; Pass="NatashaPass123!"; Dept="Engineering"; Title="Software Engineer"; Groups=@("Engineering_Users"); Manager="steve.rogers"},
    @{Name="sam.wilson"; Pass="SamPass123!"; Dept="Operations"; Title="Operations Manager"; Groups=@("Operations_Users"); Manager="patricia.coo"},
    @{Name="bucky.barnes"; Pass="BuckyPass123!"; Dept="Operations"; Title="Facilities"; Groups=@("Operations_Users","Asset_Management"); Manager="sam.wilson"},
    @{Name="matt.murdock"; Pass="MattPass123!"; Dept="Legal"; Title="Legal Counsel"; Groups=@("Legal_Users"); Manager="sarah.ceo"},
    @{Name="nick.fury"; Pass="NickPass123!"; Dept="Compliance"; Title="Compliance Officer"; Groups=@("Compliance_Users"); Manager="sarah.ceo"},
    @{Name="contractor.temp1"; Pass="TempPass123!"; Dept="Temp-Contractors"; Title="IT Contractor"; Groups=@("Temp_Contractors","IT_Users"); Manager="robert.cio"},
    @{Name="contractor.temp2"; Pass="TempPass456!"; Dept="Temp-Contractors"; Title="Security Consultant"; Groups=@("Temp_Contractors","Security_Users"); Manager="james.ciso"},
    @{Name="vendor.microsoft"; Pass="VendorPass123!"; Dept="Vendors"; Title="Microsoft Rep"; Groups=@("Vendor_Users"); Manager="robert.cio"},
    @{Name="vendor.oracle"; Pass="VendorPass456!"; Dept="Vendors"; Title="Oracle Rep"; Groups=@("Vendor_Users"); Manager="robert.cio"}
  )

  Log "Creating remaining users..."
  foreach ($u in $restOfUsers) {
    $userPass = ConvertTo-SecureString $u.Pass -AsPlainText -Force
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Name)'" -ErrorAction SilentlyContinue)) {
      $firstName = ($u.Name.Split('.')[0]).Substring(0,1).ToUpper() + ($u.Name.Split('.')[0]).Substring(1)
      $lastName = ($u.Name.Split('.')[1]).Substring(0,1).ToUpper() + ($u.Name.Split('.')[1]).Substring(1)
      try {
        New-ADUser -Name $u.Name -SamAccountName $u.Name -UserPrincipalName "$($u.Name)@$domainName" -GivenName $firstName -Surname $lastName -DisplayName "$firstName $lastName" -Title $u.Title -Department $u.Dept -AccountPassword $userPass -Enabled $true -Path "OU=$($u.Dept),OU=Users,$labOU" -PasswordNeverExpires $true -ErrorAction Stop
        Log "Created user: $($u.Name)"
      } catch {
        Log "WARNING: Could not create user $($u.Name): $_"
      }
    }
  }

  Log "Waiting 60 seconds for AD replication..."
  Start-Sleep -Seconds 60

  $allUsers = $executives + $restOfUsers
  Log "Adding users to groups..."
  foreach ($u in $allUsers) {
    $userExists = Get-ADUser -Filter "SamAccountName -eq '$($u.Name)'" -ErrorAction SilentlyContinue
    if ($userExists) {
      foreach ($g in $u.Groups) {
        $groupExists = Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue
        if ($groupExists) {
          try {
            Add-ADGroupMember -Identity $g -Members $u.Name -ErrorAction SilentlyContinue
            Log "Added $($u.Name) to group: $g"
          } catch {
            Log "WARNING: Could not add $($u.Name) to group $g: $_"
          }
        }
      }
    }
  }

  Log "Setting manager relationships..."
  $maxManagerRetries = 15
  $managerRetryDelay = 20

  foreach ($u in $allUsers) {
    if ($u.Manager) {
      $retryCount = 0
      $managerSet = $false

      while ($retryCount -lt $maxManagerRetries -and -not $managerSet) {
        try {
          $userObj = Get-ADUser -Filter "SamAccountName -eq '$($u.Name)'" -ErrorAction SilentlyContinue
          $managerObj = Get-ADUser -Filter "SamAccountName -eq '$($u.Manager)'" -ErrorAction SilentlyContinue

          if ($userObj -and $managerObj) {
            Set-ADUser -Identity $u.Name -Manager $managerObj -ErrorAction Stop
            Log "Set $($u.Manager) as manager for $($u.Name)"
            $managerSet = $true
          } else {
            $retryCount++
            if ($retryCount -lt $maxManagerRetries) {
              Start-Sleep -Seconds $managerRetryDelay
            }
          }
        } catch {
          $retryCount++
          if ($retryCount -lt $maxManagerRetries) {
            Start-Sleep -Seconds $managerRetryDelay
          }
        }
      }
    }
  }

  $serviceAccounts = @(
    @{Name="svc_sql"; Pass="SqlSvcPass123!"; Desc="SQL Service Account"; Groups=@("Server_Admins","DBA_Group","SG_SQL_Admins")},
    @{Name="svc_backup"; Pass="BackupPass123!"; Desc="Backup Service Account"; Groups=@("Backup_Operators","SG_Backup_Operators")},
    @{Name="svc_monitoring"; Pass="MonitorPass123!"; Desc="Monitoring Service Account"; Groups=@("IT_Users")},
    @{Name="svc_print"; Pass="PrintPass123!"; Desc="Print Spooler Service"; Groups=@("SG_Print_Operators")},
    @{Name="svc_web"; Pass="WebPass123!"; Desc="Web Application Pool"; Groups=@("IT_Users")},
    @{Name="svc_join"; Pass="@@DOMAIN_JOIN_PASS_DQ@@"; Desc="Domain Join Service Account"; Groups=@("Domain Computers")}
  )

  foreach ($sa in $serviceAccounts) {
    $saPass = ConvertTo-SecureString $sa.Pass -AsPlainText -Force
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($sa.Name)'" -ErrorAction SilentlyContinue)) {
      New-ADUser -Name $sa.Name -SamAccountName $sa.Name -AccountPassword $saPass -Enabled $true -Description $sa.Desc -PasswordNeverExpires $true -Path "OU=Managed,OU=ServiceAccounts,$labOU"
      Log "Created service account: $($sa.Name)"
      foreach ($g in $sa.Groups) { Add-ADGroupMember -Identity $g -Members $sa.Name -ErrorAction SilentlyContinue }
    }
  }

  dsacls "CN=Computers,$domainDN" /G "LAB\svc_join:CCDC;computer" 2>$null

  $asrepPass = ConvertTo-SecureString "ServiceP@ss1" -AsPlainText -Force
  if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_asrep'" -ErrorAction SilentlyContinue)) {
    New-ADUser -Name "svc_asrep" -SamAccountName "svc_asrep" -AccountPassword $asrepPass -Enabled $true -PasswordNeverExpires $true -Description "AS-REP Roasting Target" -Path "OU=Legacy,OU=ServiceAccounts,$labOU"
  }
  Set-ADUser "svc_asrep" -Replace @{userAccountControl = 4194304} -ErrorAction SilentlyContinue

  $kerbPass = ConvertTo-SecureString "ServiceP@ss2" -AsPlainText -Force
  if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_kerberoast'" -ErrorAction SilentlyContinue)) {
    New-ADUser -Name "svc_kerberoast" -SamAccountName "svc_kerberoast" -AccountPassword $kerbPass -Enabled $true -PasswordNeverExpires $true -Description "Kerberoasting Target" -Path "OU=Managed,OU=ServiceAccounts,$labOU"
  }
  setspn -S "MSSQLSvc/DB01.lab.local:1433" "svc_kerberoast" 2>$null

  $delegatePass = ConvertTo-SecureString "DelegateP@ss123" -AsPlainText -Force
  if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_delegate'" -ErrorAction SilentlyContinue)) {
    New-ADUser -Name "svc_delegate" -SamAccountName "svc_delegate" -AccountPassword $delegatePass -Enabled $true -PasswordNeverExpires $true -Description "Constrained Delegation" -Path "OU=ServiceAccounts,$labOU"
  }
  setspn -S "HTTP/CA01-ESC.lab.local" "svc_delegate" 2>$null
  setspn -S "CIFS/PRINT01.lab.local" "svc_delegate" 2>$null

  $cpassword = "edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw/NglVmQ"
  $gppXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Groups>
  <User name="LocalAdmin" newName="" fullName="" description="" changed="2024-03-16 10:23:45" uid="{12345678-1234-1234-1234-123456789012}">
    <Properties cpassword="$cpassword" userName="LocalAdmin" expires="2025-03-16"/>
  </User>
</Groups>
"@
  $gppXml | Out-File "C:\\Windows\\SYSVOL\\sysvol\\$domainName\\scripts\\Groups.xml" -Force

  Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction SilentlyContinue

  $adminPass = ConvertTo-SecureString "Passw0rd!" -AsPlainText -Force
  Set-ADAccountPassword -Identity "Administrator" -NewPassword $adminPass -Reset -ErrorAction SilentlyContinue
  Enable-ADAccount -Identity "Administrator" -ErrorAction SilentlyContinue

  $computers = @("WS-IT-001","WS-SEC-001","SRV-FILE-01","SQL01","WEB01","PRINT01","LINUX01")
  foreach ($c in $computers) {
    New-ADComputer -Name $c -Path "OU=Servers,OU=Computers,$labOU" -Enabled $true -ErrorAction SilentlyContinue
  }

  $dcIP = "172.28.10.21"
  $dnsRecords = @{
    "DC01" = $dcIP
    "DB01" = "172.28.10.23"
    "WIN10" = "172.28.20.30"
    "kali" = "172.28.99.10"
    "metasploitable2" = "172.28.40.12"
    "juice-shop" = "172.28.40.15"
    "LLM01" = "172.28.30.60"
    "LINUX01" = "172.28.30.72"
    "PRINT01" = "172.28.30.73"
    "cloud-pentest" = "172.28.30.80"
    "CA01-ESC" = "172.28.10.25"
  }
  foreach ($name in $dnsRecords.Keys) {
    Add-DnsServerResourceRecordA -Name $name -ZoneName "$domainName" -IPv4Address $dnsRecords[$name] -ErrorAction SilentlyContinue
  }

  # MODERN ATTACK VECTORS - COMPLETELY PRESERVED
  Log "Configuring modern attack vectors..."

  # ZeroLogon
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" /v "FullSecureChannelProtection" /t REG_DWORD /d 0 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" /v "VulnerableChannelAllowList" /t REG_MULTI_SZ /d "DC01$" /f 2>$null
  Log "ZeroLogon enabled"

  # PetitPotam
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "RestrictRemoteSAM" /t REG_DWORD /d 0 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "RemoteRestrictedAdmin" /t REG_DWORD /d 0 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v "RestrictNullSessAccess" /t REG_DWORD /d 0 /f 2>$null
  Log "PetitPotam enabled"

  # Shadow Credentials
  try {
    Set-ADDomain -Identity "$domainName" -KeyCredentialLinkEnabled $true -ErrorAction SilentlyContinue
    $vulnComp = Get-ADComputer -Filter "Name -eq 'VULN-WORKSTATION'" -ErrorAction SilentlyContinue
    if (-not $vulnComp) {
      New-ADComputer -Name "VULN-WORKSTATION" -Path "OU=Workstations,OU=Computers,$labOU" -Enabled $true -ErrorAction SilentlyContinue
    }
  } catch {}

  # NoPac
  $nopacComp = Get-ADComputer -Filter "Name -eq 'NOPAC-TARGET'" -ErrorAction SilentlyContinue
  if (-not $nopacComp) {
    New-ADComputer -Name "NOPAC-TARGET" -Path "OU=Workstations,OU=Computers,$labOU" -Enabled $true -ErrorAction SilentlyContinue
  }
  try {
    Set-ADDomain -Identity "$domainName" -Replace @{"msDS-EnablePACValidation" = $false} -ErrorAction SilentlyContinue
  } catch {}

  # RBCD
  $rbcdComp = Get-ADComputer -Filter "Name -eq 'RBCD-TARGET'" -ErrorAction SilentlyContinue
  if (-not $rbcdComp) {
    New-ADComputer -Name "RBCD-TARGET" -Path "OU=Workstations,OU=Computers,$labOU" -Enabled $true -ErrorAction SilentlyContinue
  }
  try {
    $win10 = Get-ADComputer -Filter "Name -eq 'WIN10'" -ErrorAction SilentlyContinue
    if ($win10) {
      Set-ADComputer -Identity $win10 -PrincipalsAllowedToDelegateToAccount (Get-ADComputer "DC01") -ErrorAction SilentlyContinue
    }
  } catch {}

  # PrintNightmare
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print" /v "RpcAuthnLevelPrivacyEnabled" /t REG_DWORD /d 0 /f 2>$null
  reg add "HKLM\Software\Policies\Microsoft\Windows NT\Printers" /v "RegisterSpoolerRemoteRpcEndPoint" /t REG_DWORD /d 2 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print" /v "AllowInsecureGuestAuth" /t REG_DWORD /d 1 /f 2>$null
  net localgroup administrators "DOMAIN\Domain Users" /add 2>$null
  Log "PrintNightmare enabled"

  # SMB Signing disabled
  Set-SmbServerConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $false -Force -ErrorAction SilentlyContinue
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f 2>$null
  Log "SMB signing disabled"

  # LLMNR/NBNS poisoning
  reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v "EnableMulticast" /t REG_DWORD /d 1 /f 2>$null
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" /v "NodeType" /t REG_DWORD /d 1 /f 2>$null
  Log "LLMNR/NBNS poisoning enabled"

  gpupdate /force 2>$null
  Start-Sleep -Seconds 10
  Restart-Service netlogon -Force -ErrorAction SilentlyContinue

  "DC01 configured with 45+ users at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File C:\\DC-FINAL.txt -Force

  Write-Host "================================================================================"
  Write-Host "SUCCESS: DC01 FULLY CONFIGURED"
  Write-Host "================================================================================"
  Write-Host "DOMAIN: $domainName"
  Write-Host "DC IP: $dcIP"
  Write-Host ""
  Write-Host "LAB ADMIN: labadmin / LabAdmin123!"
  Write-Host "Built-in Admin: Administrator / Passw0rd!"
  Write-Host ""
  Write-Host "45+ USERS CREATED across all departments"
  Write-Host "================================================================================"

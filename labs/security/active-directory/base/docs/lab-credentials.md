# Active Directory Pentest Lab — Complete Credential Matrix

## Intentional Training Credentials — Read First

This file contains deliberately exposed and weak credentials created exclusively for an isolated, intentionally vulnerable Active Directory lab.

These accounts and passwords are:

- Not real.
- Not reused anywhere.
- Not representative of secure practices.

They exist solely to support penetration-testing training and hands-on practice of common Active Directory attack paths.

Do not replicate these patterns in production environments.

---

## Table of Contents

- Domain Information
- Domain Admin Accounts
- Service Accounts
- Departmental Users
- Local Accounts
- Database Credentials
- Web Application Credentials
- Cloud Credentials
- GPP Credentials
- Attack Vector Mapping
- Machine Accounts
- Usage Notes
- Quick Reference

---

## Domain Information

```yaml
DOMAIN_INFO:
  domain_name: "lab.local"
  domain_netbios: "LAB"
  domain_controller: "dc01.lab.local"
  dc_ip: "172.28.128.21"
  subnet: "172.28.128.0/24"
  vagrant_network: "vagrant0"
  nat_network: "192.168.121.0/24"
```

---

## Domain Admin Accounts

<details>
<summary>Expand</summary>

```yaml
DOMAIN_ADMINS:
  - username: "labadmin"
    password: "LabAdmin123!"
    description: "Primary lab domain administrator"
    groups: ["Domain Admins", "Enterprise Admins", "Schema Admins"]

  - username: "Administrator"
    password: "Passw0rd!"
    description: "Built-in Windows domain administrator"
    groups: ["Domain Admins", "Enterprise Admins"]

  - username: "vagrant"
    password: "Vagrant123!"
    description: "Default vagrant user with domain admin rights"
    groups: ["Domain Admins"]
```

</details>

---

## Service Accounts

<details>
<summary>Expand</summary>

```yaml
SERVICE_ACCOUNTS:
  - username: "svc_asrep"
    password: "ServiceP@ss1"
    description: "AS-REP roasting target with pre-authentication disabled"
    attack_vector: "AS-REP Roasting"

  - username: "svc_kerberoast"
    password: "ServiceP@ss2"
    description: "Kerberoasting target with multiple SPNs"
    attack_vector: "Kerberoasting"
    spn:
      - "MSSQLSvc/DB01.lab.local:1433"

  - username: "svc_delegate"
    password: "DelegateP@ss123"
    description: "Constrained delegation target"
    attack_vector: "Constrained Delegation"

  - username: "svc_sql"
    password: "SqlSvcPass123!"
    description: "SQL Server service account"
    attack_vector: "SQL abuse / privilege escalation"

  - username: "svc_caadmin"
    password: "CaAdminP@ss1"
    description: "Certificate Authority service account"
    attack_vector: "AD CS abuse"

  - username: "svc_print"
    password: "PrintPass123!"
    description: "Print Spooler service account"
    attack_vector: "PrintNightmare"

  - username: "svc_backup"
    password: "BackupPass123!"
    description: "Backup service account"
    attack_vector: "Backup privilege abuse"

  - username: "svc_monitoring"
    password: "MonitorPass123!"
    description: "Monitoring service account"
    attack_vector: "Kerberoasting"

  - username: "svc_web"
    password: "WebPass123!"
    description: "Web application pool identity"
    attack_vector: "Kerberoasting"

  - username: "svc_join"
    password: "JoinP@ss!"
    description: "Domain join service account"
    attack_vector: "Kerberoasting"

  - username: "svc_webapp"
    password: "WebAppP@ss123"
    description: "Extra Kerberoast target"
    attack_vector: "Kerberoasting"

  - username: "svc_apppool"
    password: "AppPoolP@ss123"
    description: "Extra Kerberoast target"
    attack_vector: "Kerberoasting"

  - username: "svc_mssql2"
    password: "MssqlP@ss123"
    description: "Extra Kerberoast target"
    attack_vector: "Kerberoasting"

  - username: "svc_sql_gmsa"
    password: "GmsaP@ss123!"
    description: "Group-managed service account (gMSA)"
    attack_vector: "gMSA Abuse"
```

</details>

---

## Departmental Users

<details>
<summary>Expand</summary>

```yaml
DEPARTMENTAL_USERS:
  - username: "john.doe"
    password: "Password123!"
    department: "IT"
    description: "Helpdesk user"

  - username: "alice.brown"
    password: "GPOP@ss789!"
    department: "Security"
    description: "Security analyst with AD CS-related rights"

  - username: "susan.white"
    password: "Summer2024!"
    department: "HR"

  - username: "david.green"
    password: "FinanceP@ssword"
    department: "Finance"
```

</details>

---

## Local Accounts

<details>
<summary>Expand</summary>

```yaml
LOCAL_ACCOUNTS:
  WINDOWS:
    - username: "vagrant"
      password: "vagrant"
      host: "All Windows VMs"

    - username: "localadmin"
      password: "P@ssw0rd!"
      host: "All Windows systems"

  LINUX:
    - username: "root"
      password: "toor"
      host: "Linux VMs"
```

> **Note:** `llm01` does not have a password-based login account. The lab app runs as
> an unprivileged, no-shell service account (`llmlab`, `/usr/sbin/nologin`) under
> systemd — see [`llm-lab/README.md`](../llm-lab/README.md#safety-model). Access
> `llm01` via `vagrant ssh llm01` (key-based) or the API directly.

</details>

---

## Database Credentials

<details>
<summary>Expand</summary>

```yaml
DATABASE_CREDENTIALS:
  - type: "MS-SQL"
    host: "db01.lab.local"
    username: "sa"
    password: "SaAdmin123!"

  - type: "MS-SQL"
    host: "db01.lab.local"
    username: "app_user"
    password: "AppUserPass55"
```

</details>

---

## Web Application Credentials

<details>
<summary>Expand</summary>

```yaml
WEB_APPLICATION_CREDENTIALS:
  - application: "OWASP Juice Shop"
    host: "juice-shop.lab.local"
    username: "admin@juice-sh.op"
    password: "admin123"
    description: "Default administrator account for web exploitation."
```

</details>

---

## Cloud Credentials

<details>
<summary>Expand</summary>

```yaml
CLOUD_CREDENTIALS: []
```

</details>

---

## GPP Credentials

```yaml
GPP_CREDENTIALS:
  cpassword: "edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw/NglVmQ"
  decrypted_password: "GPPmidnight123"
  location: "\\\\dc01.lab.local\\SYSVOL\\lab.local\\scripts\\Groups.xml"
  username: "LocalAdmin"
```

---

## Attack Vector Mapping

<details>
<summary>Expand</summary>

```yaml
ATTACK_VECTORS:
  - ASREP_ROASTING
  - KERBEROASTING
  - AD_CS_ABUSE
  - PASSWORD_SPRAYING
  - LATERAL_MOVEMENT
  - GMSA_ABUSE
```

</details>

---

## Machine Accounts

```yaml
MACHINE_ACCOUNTS: []
```

---

## Usage Notes

```yaml
USAGE_NOTES: |
  This lab is intentionally vulnerable.
  Use only in isolated environments.
  Do not expose it to production networks.
```

---

## Quick Reference

```yaml
QUICK_REFERENCE:
  domain_admin: "labadmin:LabAdmin123!"
  builtin_admin: "Administrator:Passw0rd!"
  helpdesk: "john.doe:Password123!"
  security: "alice.brown:GPOP@ss789!"
  sql_service: "svc_sql:SqlSvcPass123!"
  asrep_target: "svc_asrep:ServiceP@ss1"
  kerberoast_target: "svc_kerberoast:ServiceP@ss2"
```
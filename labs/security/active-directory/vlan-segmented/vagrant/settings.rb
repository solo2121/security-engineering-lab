# Credentials, timeouts and WAN settings
# Domain-join and Vagrant passwords, WinRM timeouts, WAN network constants.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# DOMAIN JOIN CREDENTIALS - FIXED
# ------------------------------------------------------------
DOMAIN_JOIN_USER = ENV.fetch("DOMAIN_JOIN_USER", "svc_join")
DOMAIN_JOIN_PASS = ENV.fetch("DOMAIN_JOIN_PASS", "JoinP@ss!")

# ------------------------------------------------------------
# VAGRANT DEFAULT PASSWORD
# ------------------------------------------------------------
VAGRANT_DEFAULT_PASSWORD = ENV.fetch("VAGRANT_DEFAULT_PASSWORD", "vagrant")
VAGRANT_UPDATED_PASSWORD = ENV.fetch("VAGRANT_UPDATED_PASSWORD", "Vagrant123!")

# ------------------------------------------------------------
# WINRM TIMEOUT CONSTANTS - FIXED
# ------------------------------------------------------------
WINRM_BOOT_TIMEOUT_DEFAULT = 7200
WINRM_COMM_TIMEOUT_DEFAULT = 3600
WINRM_BOOT_TIMEOUT_DC = 10800  # Extended for DC01 AD promotion
WINRM_COMM_TIMEOUT_DC = 7200   # Extended for DC01 complex operations

# ==============================================================================
# WAN NETWORK CONFIG (dedicated network for OPNsense WAN + Kali NAT)
# ==============================================================================
WAN_NETWORK = "br-wan"
WAN_SUBNET  = "192.168.100.0"
WAN_GATEWAY = "192.168.100.1"
WAN_DHCP_START = "192.168.100.100"
WAN_DHCP_END   = "192.168.100.200"

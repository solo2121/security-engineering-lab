# Lab constants
# Attacker box, domain settings and the per-VM IP, memory and CPU tables.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# ATTACKER BOX SELECTION
# ------------------------------------------------------------
# Defaults to Kali Linux. Override with KALI_BOX / KALI_BOX_VERSION to
# use a different Debian-based pentesting distribution as the "kali"
# VM instead - for example Parrot Security:
#   KALI_BOX=ParrotSec/Parrot-security-7.3-libvirt-amd64 KALI_BOX_VERSION=7.3 vagrant up
# Verify the box name/version on Vagrant Cloud before overriding; not
# every box publishes every provider (libvirt/virtualbox) or version.
KALI_BOX = ENV.fetch('KALI_BOX', 'kalilinux/rolling')
KALI_BOX_VERSION = ENV.fetch('KALI_BOX_VERSION', '2026.1.0')

# ------------------------------------------------------------
# DOMAIN CONSTANTS
# ------------------------------------------------------------
DOMAIN_NAME = ENV.fetch('DOMAIN_NAME', 'lab.local')
DOMAIN_NETBIOS = ENV.fetch('DOMAIN_NETBIOS', 'LAB')
DC_IP = ENV.fetch('DC_IP', '172.28.128.21')
LAB_SUBNET = ENV.fetch('LAB_SUBNET', '172.28.128.0/24')
LAB_NET = ENV.fetch('LAB_NET', 'vagrant0')

# ------------------------------------------------------------
# CENTRALIZED VM CONSTANTS
# ------------------------------------------------------------
VM_IPS = {
  kali: ENV.fetch('KALI_IP', '172.28.128.10'),
  dc01: ENV.fetch('DC01_IP', '172.28.128.21'),
  db01: ENV.fetch('DB01_IP', '172.28.128.23'),
  ca01_esc: ENV.fetch('CA01_ESC_IP', '172.28.128.25'),
  win10: ENV.fetch('WIN10_IP', '172.28.128.30'),
  linux01: ENV.fetch('LINUX01_IP', '172.28.128.72'),
  print01: ENV.fetch('PRINT01_IP', '172.28.128.73'),
  llm01: ENV.fetch('LLM01_IP', '172.28.128.60'),
  metasploitable2: ENV.fetch('METASPLOITABLE2_IP', '172.28.128.12'),
  juice_shop: ENV.fetch('JUICE_SHOP_IP', '172.28.128.15'),
  cloud_pentest: ENV.fetch('CLOUD_PENTEST_IP', '172.28.128.80')
}

VM_MEMORY = {
  kali: ENV.fetch('KALI_MEMORY', 4096).to_i,
  dc01: ENV.fetch('DC01_MEMORY', 4096).to_i,
  db01: ENV.fetch('DB01_MEMORY', 4096).to_i,
  ca01_esc: ENV.fetch('CA01_ESC_MEMORY', 4096).to_i,
  win10: ENV.fetch('WIN10_MEMORY', 2048).to_i,
  linux01: ENV.fetch('LINUX01_MEMORY', 1024).to_i,
  print01: ENV.fetch('PRINT01_MEMORY', 2048).to_i,
  llm01: ENV.fetch('LLM01_MEMORY', 4096).to_i,
  metasploitable2: ENV.fetch('METASPLOITABLE2_MEMORY', 512).to_i,
  juice_shop: ENV.fetch('JUICE_SHOP_MEMORY', 2048).to_i,
  cloud_pentest: ENV.fetch('CLOUD_PENTEST_MEMORY', 2048).to_i
}

VM_CPUS = {
  kali: ENV.fetch('KALI_CPUS', 2).to_i,
  dc01: ENV.fetch('DC01_CPUS', 2).to_i,
  db01: ENV.fetch('DB01_CPUS', 2).to_i,
  ca01_esc: ENV.fetch('CA01_ESC_CPUS', 2).to_i,
  win10: ENV.fetch('WIN10_CPUS', 2).to_i,
  linux01: ENV.fetch('LINUX01_CPUS', 1).to_i,
  print01: ENV.fetch('PRINT01_CPUS', 2).to_i,
  llm01: ENV.fetch('LLM01_CPUS', 4).to_i,
  metasploitable2: ENV.fetch('METASPLOITABLE2_CPUS', 1).to_i,
  juice_shop: ENV.fetch('JUICE_SHOP_CPUS', 2).to_i,
  cloud_pentest: ENV.fetch('CLOUD_PENTEST_CPUS', 2).to_i
}

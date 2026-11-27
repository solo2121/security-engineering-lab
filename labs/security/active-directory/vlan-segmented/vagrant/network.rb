# VLAN network
# VLAN_CONFIG, WAN_VLAN, vlan_ip and MAC generation.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# VLAN DEFINITIONS
# ==============================================================================
require 'ipaddr'

# Network names and MAC OUI differ by provider: libvirt uses bridge names
# (br-*) with its own DHCP config for the bridge itself (VLAN hosts still
# get static IPs; OPNsense serves DHCP on each VLAN as configured below),
# while VirtualBox uses internal network names (vlan*) with no bridge-level
# DHCP concept. MAC OUIs follow each hypervisor's convention (52:54:00 for
# QEMU/KVM, 08:00:27 for VirtualBox) purely for realism/traceability.
VLAN_CONFIG = if PROVIDER == :libvirt
  {
    10 => { name: "br-mgmt",         subnet: "172.28.10.0/24",  gateway: "172.28.10.1", description: "Management Network (AD Infrastructure)", dhcp_start: "172.28.10.100", dhcp_end: "172.28.10.200" },
    20 => { name: "br-workstations", subnet: "172.28.20.0/24",  gateway: "172.28.20.1", description: "Workstations VLAN (User Endpoints)", dhcp_start: "172.28.20.100", dhcp_end: "172.28.20.200" },
    30 => { name: "br-servers",      subnet: "172.28.30.0/24",  gateway: "172.28.30.1", description: "Servers VLAN (Application / DB Servers)", dhcp_start: "172.28.30.100", dhcp_end: "172.28.30.200" },
    40 => { name: "br-dmz",          subnet: "172.28.40.0/24",  gateway: "172.28.40.1", description: "DMZ Network (External-Facing Services)", dhcp_start: "172.28.40.100", dhcp_end: "172.28.40.200" },
    99 => { name: "br-attacker",     subnet: "172.28.99.0/24",  gateway: "172.28.99.1", description: "Attacker VLAN (Red Team / Kali)", dhcp_start: "172.28.99.100", dhcp_end: "172.28.99.200" }
  }
else
  {
    10 => { name: "vlan10-mgmt",         subnet: "172.28.10.0/24",  gateway: "172.28.10.1", description: "Management Network (AD Infrastructure)" },
    20 => { name: "vlan20-workstations", subnet: "172.28.20.0/24",  gateway: "172.28.20.1", description: "Workstations VLAN (User Endpoints)" },
    30 => { name: "vlan30-servers",      subnet: "172.28.30.0/24",  gateway: "172.28.30.1", description: "Servers VLAN (Application / DB Servers)" },
    40 => { name: "vlan40-dmz",          subnet: "172.28.40.0/24",  gateway: "172.28.40.1", description: "DMZ Network (External-Facing Services)" },
    99 => { name: "vlan99-attacker",     subnet: "172.28.99.0/24",  gateway: "172.28.99.1", description: "Attacker VLAN (Red Team / Kali)" }
  }
end

WAN_VLAN = { name: "vlan-wan", subnet: "192.168.100.0/24", gateway: "192.168.100.1" }

def vlan_ip(vlan_id, host_number)
  net = IPAddr.new(VLAN_CONFIG[vlan_id][:subnet])
  net.to_range.to_a[host_number].to_s
end

# ==============================================================================
# MAC ADDRESS GENERATION - FOR STABILITY
# ==============================================================================
def generate_vlan_mac(vlan_id, host_number)
  if PROVIDER == :libvirt
    "52:54:00:%02x:00:%02x" % [vlan_id & 0xff, host_number & 0xff]
  else
    "08:00:27:%02x:%02x:%02x" % [vlan_id & 0xff, (host_number >> 8) & 0xff, host_number & 0xff]
  end
end

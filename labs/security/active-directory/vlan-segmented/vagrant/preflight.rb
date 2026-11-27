# Pre-flight helpers
# libvirt network creation, RAM total and host requirement checks.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# ZERO-TOUCH SETUP HELPERS
# ==============================================================================

def ensure_libvirt_networks
  required_networks = %w[br-wan br-mgmt br-workstations br-servers br-dmz br-attacker]
  missing_networks = []

  required_networks.each do |net|
    unless system("virsh net-info #{net} > /dev/null 2>&1")
      missing_networks << net
    end
  end

  if missing_networks.empty?
    puts "[OK] All libvirt networks exist"
    return true
  end

  puts "[WARN] Missing libvirt networks: #{missing_networks.join(', ')}"

  if system("virsh net-define /dev/null > /dev/null 2>&1")
    puts "Attempting to create missing networks..."

    missing_networks.each do |net|
      if net == WAN_NETWORK
        # br-wan gets NAT + DHCP (internet access for OPNsense WAN / Kali)
        xml = <<~XML
          <network>
            <name>#{net}</name>
            <forward mode='nat'/>
            <bridge name='#{net}' stp='on' delay='0'/>
            <ip address='#{WAN_GATEWAY}' netmask='255.255.255.0'>
              <dhcp>
                <range start='#{WAN_DHCP_START}' end='#{WAN_DHCP_END}'/>
              </dhcp>
            </ip>
          </network>
        XML
      else
        # VLAN bridges are isolated (forward mode='none'), no DHCP.
        # OPNsense will provide DHCP on each VLAN.
        vlan_id = case net
                  when "br-mgmt" then 10
                  when "br-workstations" then 20
                  when "br-servers" then 30
                  when "br-dmz" then 40
                  when "br-attacker" then 99
                  end
        cfg = VLAN_CONFIG[vlan_id]
        # Defined with a native 802.1Q portgroup for advanced trunking capabilities.
        xml = <<~XML
          <network>
            <name>#{net}</name>
            <forward mode='none'/>
            <bridge name='#{net}' stp='on' delay='0'/>
            <portgroup name='vlan-#{vlan_id}' default='yes'>
              <vlan><tag id='#{vlan_id}'/></vlan>
            </portgroup>
            <ip address='#{cfg[:gateway]}' netmask='255.255.255.0'/>
          </network>
        XML
      end

      temp_file = "/tmp/#{net}.xml"
      File.write(temp_file, xml)

      if system("virsh net-define #{temp_file} 2>/dev/null") &&
         system("virsh net-autostart #{net} 2>/dev/null") &&
         system("virsh net-start #{net} 2>/dev/null")
        puts "[OK] Created network: #{net}"
        File.delete(temp_file)
      else
        puts "[WARN] Could not automatically create #{net}"
        File.delete(temp_file)
        return false
      end
    end
    true
  else
    puts "[WARN] No permissions to create libvirt networks"
    return false
  end
end

def ensure_virtualbox_networks
  puts "[OK] VirtualBox internal networks will be created as needed"
  true
end

def ensure_provider_networks
  PROVIDER == :libvirt ? ensure_libvirt_networks : ensure_virtualbox_networks
end

def calculate_total_memory(profile = LAB_PROFILE)
  vms = PROFILES[profile][:vms]
  total = 0
  vms.each do |vm_name|
    total += VM_CONFIG[vm_name][:memory] if VM_CONFIG[vm_name]
  end
  total
end

def validate_host_requirements
  ram_mb = detect_total_ram_mb
  min_ram = PROFILES[LAB_PROFILE][:min_ram]
  if ram_mb == 0
    puts "[WARN] Could not detect system RAM. Assuming minimum requirements."
    ram_mb = min_ram
  end
  if ram_mb < min_ram
    puts "[WARN] Your system has #{ram_mb}MB RAM but the #{LAB_PROFILE} profile requires at least #{min_ram}MB."
  end
  if detect_disk_space_mb < 20480
    puts "[WARN] Low disk space (#{detect_disk_space_mb/1024}GB available)."
  end
end

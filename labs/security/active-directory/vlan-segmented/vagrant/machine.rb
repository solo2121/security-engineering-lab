# Per-VM definition
# define_vm: box, communicator, NICs, common provisioners, then the role-specific provisioner.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def define_vm(config, vm_name, vm_config)
  config.vm.define vm_name, primary: vm_config[:primary] || false, autostart: vm_config[:autostart] || true do |vm|
    vm.vm.box = vm_config[:box]
    vm.vm.box_version = vm_config[:box_version] if vm_config[:box_version] && vm_config[:box_version] != 'latest'
    vm.vm.hostname = vm_config[:hostname]
    vm.vm.synced_folder ".", "/vagrant", disabled: true

    if vm_config[:guest] == :windows
      if vm_name == 'DC01'
        configure_windows_comm(vm, "vagrant", "vagrant", WINRM_BOOT_TIMEOUT_DC, WINRM_COMM_TIMEOUT_DC)
      else
        configure_windows_comm(vm, "vagrant", "vagrant")
      end
    end

    if vm_config[:ssh_username]
      vm.ssh.username = vm_config[:ssh_username]
      vm.ssh.password = vm_config[:ssh_password] if vm_config[:ssh_password]
      vm.ssh.insert_key = true
    else
      vm.ssh.insert_key = true if vm_config[:guest] == :linux
    end

    configure_provider(vm, vm_config)

    # ============================================================
    # NETWORK CONFIGURATION - VIRTUALBOX
    # ============================================================
    if vm_name == 'opnsense'
      # WAN network for OPNsense (Internal network)
      vm.vm.network "private_network",
        ip: "192.168.100.2",
        netmask: "255.255.255.0",
        virtualbox__intnet: "vlan-wan",
        mac: "08:00:27:00:00:01"

      # VLAN bridges for each VLAN
      [10, 20, 30, 40, 99].each_with_index do |vlan_id, idx|
        vm.vm.network "private_network",
          ip: VLAN_CONFIG[vlan_id][:gateway],
          netmask: "255.255.255.0",
          virtualbox__intnet: VLAN_CONFIG[vlan_id][:name],
          mac: "08:00:27:%02x:%02x:%02x" % [vlan_id & 0xff, ((idx+2) >> 8) & 0xff, (idx+2) & 0xff]
      end

    elsif vm_config[:nat_ip]
      # VMs with NAT IP (Kali)
      vm.vm.network "private_network",
        ip: vm_config[:nat_ip],
        netmask: "255.255.255.0",
        virtualbox__intnet: "vlan-wan",
        mac: "08:00:27:00:00:02"

      configure_vlan_network(vm, vm_config[:vlan], vm_config[:host_number], guest: vm_config[:guest])

    else
      configure_vlan_network(vm, vm_config[:vlan], vm_config[:host_number], guest: vm_config[:guest])
    end

    vlan_id = vm_config[:vlan]
    host_number = vm_config[:host_number]
    vm_ip = vlan_ip(vlan_id, host_number) rescue nil
    gateway = VLAN_CONFIG[vlan_id][:gateway] rescue nil
    dns_server = vlan_ip(10, 21) rescue DC_IP

    if vm_config[:guest] == :windows
      configure_windows_static_ip(vm, vm_ip, gateway) if vm_ip
      disable_windows_defender(vm)

      unless ['opnsense'].include?(vm_name)
        wait_for_dc(vm, DC_IP)
        domain_join_windows(vm, vm_name, DC_IP, gateway) if vm_ip
      end

    elsif vm_config[:guest] == :linux
      # OPNsense is FreeBSD-based: no /bin/bash, iproute2, or dhclient.
      # Its interfaces are configured via the opnsense-init provisioner (config.xml),
      # so the Linux network-config provisioner must be skipped here to avoid
      # "bad interpreter: /bin/bash: No such file or directory".
      configure_linux_network(vm, vm_ip, gateway, dns_server) if vm_ip && vm_name != 'opnsense'
      # FIX: All Linux VMs should get lab hosts entries
      write_lab_hosts(vm) unless vm_name == 'opnsense'
    end

    # VM-specific provisioning (one file per VM in vagrant/roles/)
    case vm_name
    when 'opnsense'
      provision_opnsense(vm)
    when 'DC01'
      provision_dc01(vm)
    when 'kali'
      provision_kali(vm)
    when 'CA01-ESC'
      provision_ca01_esc(vm, vm_ip)
    when 'DB01'
      provision_db01(vm)
    when 'WIN10'
      provision_win10(vm)
    when 'print01'
      provision_print01(vm)
    when 'llm01'
      provision_llm01(vm, vm_ip)
    when 'cloud-pentest'
      provision_cloud_pentest(vm)
    when 'juice-shop'
      provision_juice_shop(vm)
    end
  end
end

# Provider and network helpers
# VLAN NICs, Linux network config, WinRM, libvirt and VirtualBox settings.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# HELPER FUNCTIONS - VIRTUALBOX
# ==============================================================================

def configure_vlan_network(vm, vlan_id, host_number, options = {})
  cfg = VLAN_CONFIG[vlan_id]
  guest_type = options[:guest] || :linux
  mac_addr = generate_vlan_mac(vlan_id, host_number)

  if PROVIDER == :libvirt
    nic_model = guest_type == :windows ? "e1000e" : "virtio"
    vm.vm.network :private_network,
      ip: vlan_ip(vlan_id, host_number),
      netmask: "255.255.255.0",
      libvirt__network_name: cfg[:name],
      libvirt__model_type: nic_model,
      libvirt__forward_mode: "none",
      libvirt__dhcp_enabled: false,
      auto_config: false,
      libvirt__mac: mac_addr
  else
    vm.vm.network "private_network",
      ip: vlan_ip(vlan_id, host_number),
      netmask: "255.255.255.0",
      virtualbox__intnet: cfg[:name],
      mac: mac_addr
  end
end

def configure_linux_network(vm, ip_address, gateway, dns_server)
  nat_ip_prefix = PROVIDER == :libvirt ? "192.168.121" : "10.0.2"
  vm.vm.provision "shell",
    name: "linux-network-config",
    run: "once",
    inline: render_provision("linux/network-config.sh", IP_ADDRESS: ip_address, NAT_IP_PREFIX: nat_ip_prefix, GATEWAY: gateway, DNS_SERVER: dns_server)
end

def configure_windows_comm(vm, user = "vagrant", pass = "vagrant",
                          boot_timeout = WINRM_BOOT_TIMEOUT_DEFAULT,
                          winrm_timeout = WINRM_COMM_TIMEOUT_DEFAULT)
  vm.vm.communicator = "winrm"
  vm.vm.guest = :windows
  vm.vm.boot_timeout = boot_timeout

  vm.winrm.username = user
  vm.winrm.password = pass
  vm.winrm.transport = :plaintext
  vm.winrm.port = 5985
  vm.winrm.retry_limit = 240
  vm.winrm.retry_delay = 30
  vm.winrm.timeout = winrm_timeout
  vm.winrm.basic_auth_only = true
end

def configure_libvirt(vm, config)
  settings = VM_CONFIG[config[:name]] || {}

  vm.vm.provider :libvirt do |libvirt|
    libvirt.memory = config[:memory] || settings[:memory] || 1024
    libvirt.cpus = config[:cpus] || settings[:cpus] || 1
    libvirt.disk_bus = "virtio"
    libvirt.nic_model_type = config[:guest] == :windows ? "e1000e" : "virtio"
    libvirt.video_type = "vga"
    libvirt.video_vram = 16384
    # Group VMs cleanly under lab-vlan_ prefix in virsh
    libvirt.default_prefix = "lab-vlan"
    libvirt.nested = true
    libvirt.graphics_type = "vnc"
    libvirt.graphics_ip = "127.0.0.1"
    libvirt.video_accel3d = false
    libvirt.qemu_use_session = false
    libvirt.uri = 'qemu:///system'
    libvirt.mgmt_attach = true

    if config[:guest] == :windows
      libvirt.cpu_mode = "host-passthrough"
      libvirt.cpu_model = "host"
    end

    if config[:disk_size]
      libvirt.storage :file,
        size: "#{config[:disk_size]}G",
        type: "qcow2",
        bus: "virtio"
    end
  end
end

def configure_virtualbox(vm, config)
  settings = VM_CONFIG[config[:name]] || {}

  vm.vm.provider :virtualbox do |vb|
    vb.memory = config[:memory] || settings[:memory] || 1024
    vb.cpus = config[:cpus] || settings[:cpus] || 1
    vb.gui = LAB_GUI
    vb.linked_clone = true

    # Enable hardware virtualization for better performance
    vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
    vb.customize ["modifyvm", :id, "--vtxux", "on"]
    vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
    vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
    vb.customize ["modifyvm", :id, "--largepages", "on"]

    # Network settings - use virtio for better performance
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]

    # Graphics settings for Windows
    if config[:guest] == :windows
      vb.customize ["modifyvm", :id, "--vram", "128"]
      vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--usb", "on"]
      vb.customize ["modifyvm", :id, "--usbehci", "on"]
    end

    # Performance optimizations
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]

    # Network adapter order: NAT for internet, Internal for lab
    vb.customize ["modifyvm", :id, "--nic1", "nat"]

    # Storage
    if config[:disk_size]
      vb.customize ["storagectl", :id, "--name", "SATA Controller", "--add", "sata", "--controller", "IntelAHCI"]
    end
  end
end

def configure_provider(vm, config)
  PROVIDER == :libvirt ? configure_libvirt(vm, config) : configure_virtualbox(vm, config)
end

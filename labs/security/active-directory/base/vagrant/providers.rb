# Provider and network configuration
# Default VM settings, static-IP networking and the libvirt and VirtualBox setup.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# DEFAULT CONFIGURATIONS
# ------------------------------------------------------------
DEFAULT_CONFIG = {
  memory: 1024,
  cpus: 1,
  disk_bus: "virtio",
  nic_model_type: "virtio",
  video_type: "vga",
  video_vram: 16384
}.freeze

WINDOWS_CONFIG = {
  memory: 2048,
  cpus: 2,
  disk_size: 40,
  nic_model_type: "e1000e",
  guest: :windows,
  communicator: "winrm",
  boot_timeout: 7200,
  video_type: "vga",
  video_vram: 16384
}.freeze

# ------------------------------------------------------------
# NETWORK FUNCTION - STATIC IP ONLY, NO DHCP (provider-aware)
# ------------------------------------------------------------
def configure_network(vm, ip)
  if PROVIDER == :libvirt
    vm.vm.network :private_network,
      ip: ip,
      libvirt__network_name: LAB_NET,
      libvirt__forward_mode: "none",
      libvirt__dhcp_enabled: false,
      libvirt__driver_name: "qemu",
      auto_config: false
  else
    vm.vm.network "private_network", ip: ip, virtualbox__intnet: "pentest_lab"
  end
end

# ------------------------------------------------------------
# LIBVIRT PROVIDER CONFIG
# ------------------------------------------------------------
def configure_libvirt(vm, overrides = {})
  settings = DEFAULT_CONFIG.merge(overrides)

  vm.vm.provider :libvirt do |libvirt|
    libvirt.memory = settings[:memory]
    libvirt.cpus = settings[:cpus]
    libvirt.disk_bus = settings[:disk_bus]
    libvirt.nic_model_type = settings[:nic_model_type]
    libvirt.video_type = settings[:video_type]
    libvirt.video_vram = settings[:video_vram]
    libvirt.default_prefix = ""
    libvirt.nested = true
    libvirt.graphics_type = "vnc"
    libvirt.graphics_ip = "127.0.0.1"
    libvirt.video_accel3d = false
    libvirt.qemu_use_session = false
    libvirt.uri = 'qemu:///system'
    libvirt.mgmt_attach = true

    if settings[:guest] == :windows
      libvirt.cpu_mode = "host-passthrough"
      libvirt.cpu_model = "host"

      # Safely configure channel if method exists
      if libvirt.respond_to?(:channel)
        begin
          libvirt.channel type: "unix",
                          target_name: "org.qemu.guest_agent.0",
                          target_type: "virtio"
        rescue => e
          puts "[WARN] Failed to configure guest agent channel: #{e.message}"
        end
      end
    end

    if settings[:disk_size]
      libvirt.storage :file,
        size: "#{settings[:disk_size]}G",
        type: "qcow2",
        bus: "virtio"
    end
  end
end

# ------------------------------------------------------------
# VIRTUALBOX PROVIDER CONFIG
# ------------------------------------------------------------
def configure_virtualbox(vm, overrides = {})
  settings = DEFAULT_CONFIG.merge(overrides)

  vm.vm.provider :virtualbox do |vb|
    vb.memory = settings[:memory]
    vb.cpus = settings[:cpus]
    vb.gui = LAB_GUI
    vb.linked_clone = true

    # Enable hardware virtualization for better performance
    vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
    vb.customize ["modifyvm", :id, "--vtxux", "on"]
    vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
    vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
    vb.customize ["modifyvm", :id, "--largepages", "on"]

    # Network settings
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
    vb.customize ["modifyvm", :id, "--nictype2", "virtio"]

    # Graphics settings for Windows
    if settings[:guest] == :windows
      vb.customize ["modifyvm", :id, "--vram", "128"]
      vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--usb", "on"]
      vb.customize ["modifyvm", :id, "--usbehci", "on"]
    end

    # Performance optimizations
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]

    # Network adapter order: NAT for internet, Host-Only for lab
    vb.customize ["modifyvm", :id, "--nic1", "nat"]
    vb.customize ["modifyvm", :id, "--nic2", "hostonly"]
  end
end

# ------------------------------------------------------------
# PROVIDER DISPATCH - calls the configuration function matching
# the active PROVIDER so call sites don't need to branch.
# ------------------------------------------------------------
def configure_provider(vm, overrides = {})
  if PROVIDER == :libvirt
    configure_libvirt(vm, overrides)
  else
    configure_virtualbox(vm, overrides)
  end
end

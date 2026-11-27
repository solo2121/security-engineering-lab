# Provider hardware and disks
# libvirt and VirtualBox VM settings and the extra lab disks.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# PROVIDER-SPECIFIC CONFIGURATION FUNCTIONS
# =============================================================================
def configure_libvirt(vm, opts = {})
  c = DEFAULT.merge(opts)
  vm.vm.provider :libvirt do |lv|
    lv.memory = c[:memory]
    lv.cpus = c[:cpus]
    lv.nested = true
    lv.graphics_type = "vnc"
    lv.graphics_ip = "127.0.0.1"
    lv.video_type = "virtio"
    lv.cpu_mode = "host-passthrough"
  end
end

def configure_virtualbox(vm, opts = {})
  c = DEFAULT.merge(opts)
  vm.vm.provider :virtualbox do |vb|
    vb.memory = c[:memory]
    vb.cpus = c[:cpus]
    vb.gui = LAB_GUI

    # Enable nested virtualization
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]

    # Use VMSVGA graphics controller
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]

    # Enable USB 3.0 for better performance
    vb.customize ["modifyvm", :id, "--usb", "on"]
    vb.customize ["modifyvm", :id, "--usbehci", "on"]
    vb.customize ["modifyvm", :id, "--usbxhci", "on"]
  end
end

def attach_libvirt_disks(vm)
  vm.vm.provider :libvirt do |lv|
    lv.storage :file, size: "5G", type: "qcow2", cache: "writeback"
    lv.storage :file, size: "5G", type: "qcow2", cache: "writeback"
    lv.storage :file, size: "2G", type: "qcow2", cache: "writeback"
  end
end

def attach_virtualbox_disks(vm, vm_name)
  vm.vm.provider :virtualbox do |vb|
    disk_dir = File.expand_path("disks/#{vm_name}")
    FileUtils.mkdir_p(disk_dir)
    controller_name = "SATA"

    # Disk 1: 5G
    disk1 = "#{disk_dir}/disk1.vdi"
    unless File.exist?(disk1)
      vb.customize ["createmedium", "disk", "--filename", disk1, "--size", 5120, "--format", "VDI"]
    end
    vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 1, "--device", 0, "--type", "hdd", "--medium", disk1]

    # Disk 2: 5G
    disk2 = "#{disk_dir}/disk2.vdi"
    unless File.exist?(disk2)
      vb.customize ["createmedium", "disk", "--filename", disk2, "--size", 5120, "--format", "VDI"]
    end
    vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 2, "--device", 0, "--type", "hdd", "--medium", disk2]

    # Disk 3: 2G
    disk3 = "#{disk_dir}/disk3.vdi"
    unless File.exist?(disk3)
      vb.customize ["createmedium", "disk", "--filename", disk3, "--size", 2048, "--format", "VDI"]
    end
    vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 3, "--device", 0, "--type", "hdd", "--medium", disk3]
  end
end

def attach_disks(vm, vm_name)
  if PROVIDER == :libvirt
    attach_libvirt_disks(vm)
  else
    attach_virtualbox_disks(vm, vm_name)
  end
end

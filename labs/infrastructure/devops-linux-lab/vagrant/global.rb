# Global Vagrant settings
# Synced folder, timeouts, host pre-flight trigger and the lab environment file.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def configure_global(config)
  config.vm.box_check_update = false
  # /vagrant is a one-way rsync copy (host -> guest) on libvirt. The type is set
  # explicitly because, when it is left out, Vagrant picks whichever type it finds
  # usable on the host, which can be a 9p share that root inside the VM cannot
  # write to ("/vagrant/lab.env: Permission denied"). Because rsync is one-way,
  # files the master writes (.k3s_token, .cluster_state.json) are pulled back to
  # the host by a trigger on devops-1 below, and the workers receive them when
  # they boot. Start devops-1 first, then the workers.
  # SYNC_TYPE=nfs|virtiofs|9p overrides this for hosts that support it.
  if PROVIDER == :libvirt
    sync_type = ENV['SYNC_TYPE'] || "rsync"
    puts "Synced folder type: #{sync_type}"
    if sync_type == "nfs"
      config.vm.synced_folder ".", "/vagrant", type: "nfs", nfs_version: 4, nfs_udp: false
    else
      config.vm.synced_folder ".", "/vagrant", type: sync_type
    end
  else
    config.vm.synced_folder ".", "/vagrant", disabled: false
  end
  config.ssh.connect_timeout = 600
  config.vm.boot_timeout = 1200

  # VirtualBox-specific global settings
  if PROVIDER == :virtualbox
    config.vm.provider :virtualbox do |vb|
      vb.linked_clone = true
    end

    if Vagrant.has_plugin?("vagrant-vbguest")
      config.vbguest.auto_update = true
      config.vbguest.no_install = false
      config.vbguest.installer_options = { allow_kernel_upgrade: true }
    end
  end

  # Pre-flight host check
  #
  # This MUST run on the host, not inside the guest -- it checks for
  # virsh/VBoxManage, which are host-side hypervisor tools and will
  # never be present inside a stock guest VM. A `config.vm.provision`
  # "shell" block runs inside the guest, so this uses a host-side
  # `trigger.before :up` instead. Runs once per `vagrant up` invocation,
  # before any machine is created.
  config.trigger.before :up do |trigger|
    trigger.name = "Pre-flight host check"
    trigger.info = "Checking host virtualization tooling before creating any VM..."
    trigger.run = {
      path: File.expand_path("scripts/pre-flight-host-check.sh", LAB_DIR),
      args: PROVIDER.to_s
    }
  end

  # Lab environment file
  config.vm.provision "shell", inline: render_provision("common/lab-env.sh", MASTER_IP: MASTER_IP, NETWORK_BASE: NETWORK_BASE, PROVIDER: PROVIDER, OPENTOFU_VERSION: OPENTOFU_VERSION, KIND_VERSION: KIND_VERSION, K3D_VERSION: K3D_VERSION, KUBECTL_VERSION: KUBECTL_VERSION, HARBOR_PASS: HARBOR_PASSWORD)

  # Snapshot trigger
  config.trigger.before :destroy do |trigger|
    trigger.name = "Snapshot warning"
    trigger.info = "VM will be destroyed. Consider taking a snapshot first: vagrant snapshot save pre-destroy"
  end
end

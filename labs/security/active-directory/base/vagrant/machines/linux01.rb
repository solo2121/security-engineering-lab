# VM definition: linux01
# Loaded by the Vagrantfile, which calls define_linux01(config).

def define_linux01(config)
  # ===========================================================================
  # LINUX01
  # ===========================================================================
  config.vm.define "linux01" do |vm|
    vm.vm.box = "generic/ubuntu2204"
    vm.vm.box_version = "4.3.10"
    vm.vm.hostname = "linux01"

    configure_network(vm, VM_IPS[:linux01])

    configure_provider(vm, memory: VM_MEMORY[:linux01], cpus: VM_CPUS[:linux01])

    # Add SSH key for secure access
    vm.ssh.insert_key = true

    write_lab_hosts(vm)

    vm.vm.provision "shell", name: "linux01-config", inline: render_provision("linux01/linux01-config.sh")
  end
end

# VM definition: win10
# Loaded by the Vagrantfile, which calls define_win10(config).

def define_win10(config)
  # ===========================================================================
  # WIN10
  # ===========================================================================
  config.vm.define "win10" do |vm|
    vm.vm.box = "peru/windows-10-enterprise-x64-eval"
    vm.vm.hostname = "win10"
    vm.vm.synced_folder ".", "/vagrant", disabled: true
    # Use default timeouts for non-DC VMs
    configure_windows_comm(vm, "vagrant", "vagrant")

    domain_join_windows(vm, "WIN10", VM_IPS[:win10], VM_MEMORY[:win10], 30)

    vm.vm.provision "shell", name: "win10-config", privileged: true, inline: render_provision("win10/win10-config.ps1")

    disable_internet_gateway(vm, "win10")
    add_health_check(vm, "win10")
  end
end

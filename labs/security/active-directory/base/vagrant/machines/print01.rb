# VM definition: print01
# Loaded by the Vagrantfile, which calls define_print01(config).

def define_print01(config)
  # ===========================================================================
  # PRINT01
  # ===========================================================================
  config.vm.define "print01" do |vm|
    vm.vm.box = "peru/windows-server-2022-standard-x64-eval"
    vm.vm.hostname = "print01"
    vm.vm.synced_folder ".", "/vagrant", disabled: true
    # Use default timeouts for non-DC VMs
    configure_windows_comm(vm, "vagrant", "vagrant")

    domain_join_windows(vm, "PRINT01", VM_IPS[:print01], VM_MEMORY[:print01], 40)

    vm.vm.provision "shell", name: "printnightmare-config", privileged: true, inline: render_provision("print01/printnightmare-config.ps1")

    disable_internet_gateway(vm, "print01")
    add_health_check(vm, "print01")
  end
end

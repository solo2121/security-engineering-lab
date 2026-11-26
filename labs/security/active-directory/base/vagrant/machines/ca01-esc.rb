# VM definition: ca01-esc
# Loaded by the Vagrantfile, which calls define_ca01_esc(config).

def define_ca01_esc(config)
  # ===========================================================================
  # CA01-ESC - FULL AD CS VULNERABILITIES FOR ESC ATTACKS
  # ===========================================================================
  config.vm.define "ca01-esc" do |vm|
    vm.vm.box = "peru/windows-server-2022-standard-x64-eval"
    vm.vm.hostname = "ca01-esc"
    vm.vm.synced_folder ".", "/vagrant", disabled: true
    # Use default timeouts for non-DC VMs
    configure_windows_comm(vm, "vagrant", "vagrant")

    domain_join_windows(vm, "CA01-ESC", VM_IPS[:ca01_esc], VM_MEMORY[:ca01_esc], 60)

    vm.vm.provision "shell", name: "adcs-esc-setup", privileged: true, inline: render_provision("ca01-esc/adcs-esc-setup.ps1")

    disable_internet_gateway(vm, "ca01-esc")
    add_health_check(vm, "ca01-esc")
  end
end

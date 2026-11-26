# VM definition: db01
# Loaded by the Vagrantfile, which calls define_db01(config).

def define_db01(config)
  # ===========================================================================
  # DB01
  # ===========================================================================
  config.vm.define "db01" do |vm|
    vm.vm.box = "peru/windows-server-2022-standard-x64-eval"
    vm.vm.hostname = "db01"
    vm.vm.synced_folder ".", "/vagrant", disabled: true
    # Use default timeouts for non-DC VMs
    configure_windows_comm(vm, "vagrant", "vagrant")

    domain_join_windows(vm, "DB01", VM_IPS[:db01], VM_MEMORY[:db01], 40)

    vm.vm.provision "shell", name: "sql-config", privileged: true, inline: render_provision("db01/sql-config.ps1")

    disable_internet_gateway(vm, "db01")
    add_health_check(vm, "db01")
  end
end

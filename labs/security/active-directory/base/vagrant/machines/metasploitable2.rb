# VM definition: metasploitable2
# Loaded by the Vagrantfile, which calls define_metasploitable2(config).

def define_metasploitable2(config)
  # ===========================================================================
  # METASPLOITABLE2
  # ===========================================================================
  config.vm.define "metasploitable2" do |vm|
    vm.vm.box = "deargle/metasploitable2"
    vm.vm.box_version = "0.1.0"
    vm.vm.hostname = "metasploitable2"

    configure_network(vm, VM_IPS[:metasploitable2])

    configure_provider(vm, memory: VM_MEMORY[:metasploitable2], cpus: VM_CPUS[:metasploitable2])

    vm.vm.synced_folder ".", "/vagrant", disabled: true
    vm.ssh.username = "msfadmin"
    vm.ssh.password = "msfadmin"
    vm.ssh.insert_key = false  # Metasploitable2 has known SSH key

    write_lab_hosts(vm)

    vm.vm.provision "shell", name: "metasploitable2-dns", run: "once", inline: render_provision("metasploitable2/dns-config.sh", DC_IP: DC_IP, DOMAIN_NAME: DOMAIN_NAME)
  end
end

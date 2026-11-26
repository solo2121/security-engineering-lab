# VM definition: juice-shop
# Loaded by the Vagrantfile, which calls define_juice_shop(config).

def define_juice_shop(config)
  # ===========================================================================
  # JUICE-SHOP
  # ===========================================================================
  config.vm.define "juice-shop" do |vm|
    vm.vm.box = "ubuntu/jammy64"
    vm.vm.box_version = "20241007.0.0"
    vm.vm.hostname = "juice-shop"

    configure_network(vm, VM_IPS[:juice_shop])

    configure_provider(vm, memory: VM_MEMORY[:juice_shop], cpus: VM_CPUS[:juice_shop])

    vm.ssh.insert_key = true

    write_lab_hosts(vm)

    vm.vm.provision "shell", name: "juice-shop-setup", run: "once", inline: render_provision("juice-shop/juice-shop-setup.sh")
  end
end

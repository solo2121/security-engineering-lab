# juice-shop provisioning
# VM-specific provisioners for juice-shop.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_juice_shop(vm)
  vm.vm.provision "shell", run: "once", inline: render_provision("juice-shop/juice-shop-setup.sh")
end

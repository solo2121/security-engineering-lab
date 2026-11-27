# DB01 provisioning
# VM-specific provisioners for DB01.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_db01(vm)
  vm.vm.provision "shell", name: "db-config", privileged: true, run: "once", inline: render_provision("db01/db-config.ps1")

  disable_internet_gateway(vm, "db01")
end

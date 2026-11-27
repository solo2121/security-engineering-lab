# WIN10 provisioning
# VM-specific provisioners for WIN10.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_win10(vm)
  vm.vm.provision "shell", name: "win10-config", privileged: true, run: "once", inline: render_provision("win10/win10-config.ps1")

  disable_internet_gateway(vm, "win10")
end

# print01 provisioning
# VM-specific provisioners for print01.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_print01(vm)
  vm.vm.provision "shell", name: "print-config", privileged: true, run: "once", inline: render_provision("print01/print-config.ps1")

  disable_internet_gateway(vm, "print01")
end

# CA01-ESC provisioning
# VM-specific provisioners for CA01-ESC.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_ca01_esc(vm, vm_ip)
  vm.vm.provision "shell", name: "ca-esc-setup", privileged: true, run: "once", inline: render_provision("ca01-esc/adcs-esc-setup.ps1", DOMAIN_DN: build_domain_dn(DOMAIN_NAME), DOMAIN_NETBIOS: DOMAIN_NETBIOS, DOMAIN_NAME: DOMAIN_NAME, VM_IP: vm_ip)

  disable_internet_gateway(vm, "ca01-esc")
end

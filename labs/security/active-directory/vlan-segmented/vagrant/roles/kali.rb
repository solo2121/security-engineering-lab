# kali provisioning
# VM-specific provisioners for kali.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_kali(vm)
  vm.vm.provision "shell", inline: render_provision("kali/kali-config.sh")
end

# Role: lab
# provision_lab adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_lab(vm)
  vm.vm.provision "shell", inline: render_provision("ansible/lab-ssh-setup.sh")
end

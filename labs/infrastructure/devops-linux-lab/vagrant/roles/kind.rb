# Role: kind
# provision_kind adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_kind(vm)
  vm.vm.network "forwarded_port", guest: 6443, host: 26443, host_ip: "127.0.0.1"

  vm.vm.provision "shell", inline: render_provision("common/enable-docker.sh")

  vm.vm.provision "shell", inline: render_provision("kind/kind-cluster.sh")
end

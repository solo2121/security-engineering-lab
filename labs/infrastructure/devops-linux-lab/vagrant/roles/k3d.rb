# Role: k3d
# provision_k3d adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_k3d(vm)
  vm.vm.network "forwarded_port", guest: 6443, host: 26444, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 8080, host: 28080, host_ip: "127.0.0.1"

  vm.vm.provision "shell", inline: render_provision("common/enable-docker.sh")

  vm.vm.provision "shell", inline: render_provision("k3d/k3d-cluster.sh", HELM_VERSION: HELM_VERSION)
end

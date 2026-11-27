# Role: worker
# provision_worker adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_worker(vm, cfg, name)
  vm.vm.provision "shell", inline: render_provision("worker/worker-join.sh", MASTER_IP: MASTER_IP, CFG_IP: cfg[:ip], NAME: name)
end

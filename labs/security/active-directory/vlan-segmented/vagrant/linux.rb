# Linux guest helpers
# The /etc/hosts provisioner.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# LAB HOSTS FILE HELPER - Centralized /etc/hosts management
# ==============================================================================
def write_lab_hosts(vm)
  vm.vm.provision "shell",
    name: "configure-lab-hosts",
    privileged: true,
    run: "once",
    inline: render_provision("linux/lab-hosts.sh")
end

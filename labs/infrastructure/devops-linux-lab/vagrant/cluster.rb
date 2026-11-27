# VM tables
# Every lab VM, the ones to define for this run (VMS_TO_START) and the /etc/hosts entries.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

cluster = {
  "devops-1" => { box: "bento/ubuntu-24.04", ip: MASTER_IP, memory: 8192, cpus: 4, role: "master" },
  "worker-1" => { box: "bento/ubuntu-24.04", ip: vm_ip(11), memory: 2048, cpus: 2, role: "worker" },
  "worker-2" => { box: "bento/ubuntu-24.04", ip: vm_ip(12), memory: 2048, cpus: 2, role: "worker" }
}

LINUX_LABS = {
  "ubuntu-lab" => { box: "bento/ubuntu-24.04", ip: vm_ip(20), memory: 2048, cpus: 2, role: "lab" },
  "rocky-lab" => { box: "bento/rockylinux-9.6", ip: vm_ip(21), memory: 2048, cpus: 2, role: "lab" },
  "alma-lab" => { box: "bento/almalinux-9.6", ip: vm_ip(22), memory: 2048, cpus: 2, role: "lab" },
  "suse-lab" => { box: "bento/opensuse-leap-15.6", ip: vm_ip(23), memory: 2048, cpus: 2, role: "lab" }
}

ansible_nodes = {
  "node1" => { box: "bento/ubuntu-24.04", ip: vm_ip(30), memory: 1024, cpus: 1, role: "ansible" },
  "node2" => { box: "bento/ubuntu-24.04", ip: vm_ip(31), memory: 1024, cpus: 1, role: "ansible" }
}

kind_labs = {
  "kind-lab" => {
    box: "bento/ubuntu-24.04",
    ip: vm_ip(40),
    memory: 4096,
    cpus: 2,
    role: "kind"
  }
}

k3d_labs = {
  "k3d-lab" => {
    box: "bento/ubuntu-24.04",
    ip: vm_ip(41),
    memory: 4096,
    cpus: 2,
    role: "k3d"
  }
}

cicd_server = {
  "cicd-server" => {
    box: "bento/ubuntu-24.04",
    ip: vm_ip(50),
    memory: 4096,
    cpus: 2,
    role: "cicd"
  }
}

all_vms = cluster.merge(LINUX_LABS).merge(ansible_nodes).merge(kind_labs).merge(k3d_labs).merge(cicd_server)
# Machines named explicitly on the command line (vagrant up ubuntu-lab,
# vagrant ssh ubuntu-lab, vagrant status rocky-lab, ...) are always defined,
# whatever LAB_PROFILE is. Without this, any VM outside the active profile
# fails with "The machine with the name '<vm>' was not found configured for
# this Vagrant environment."
cli_vms = ARGV.select { |arg| all_vms.key?(arg) }
VMS_TO_START = all_vms.select { |name, _| should_start?(name, LAB_PROFILE, START_VMS | cli_vms) }
HOSTS_ENTRIES = all_vms.map { |n, c| "#{c[:ip]} #{n}" }.join("\n")

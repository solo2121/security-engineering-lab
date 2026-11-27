# llm01 provisioning
# VM-specific provisioners for llm01.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_llm01(vm, vm_ip)
  # OWASP Top 10 for LLM Applications (2025) training lab. The app
  # itself lives at ../base/llm-lab (shared with the base Vagrantfile
  # so there's one copy of the app, not two) — see that directory's
  # README.md for full docs. All vulnerable behavior is sandboxed
  # inside the app (see llm-lab/app/safety.py); this provisioner only
  # stages files and runs setup.
  vm.vm.provision "file", source: "../base/llm-lab", destination: "/tmp/llm-lab-src"

  # One provisioner for both labs: this uses the base lab's script, so a
  # fix there (DNS wait, Docker auto-start, egress rules) reaches this lab
  # too. The segmented lab allows egress to all of 172.28.0.0/16.
  vm.vm.provision "shell", name: "llm01-config", privileged: true, inline: render_provision("../../base/provision/llm01/llm01-config.sh", LAB_SUBNET: "172.28.0.0/16", LLM01_IP: vm_ip)
end

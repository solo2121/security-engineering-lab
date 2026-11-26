# Linux guest helpers
# Writes the lab's /etc/hosts entries.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# LAB HOSTS FILE HELPER - writes all lab VM entries to /etc/hosts
# Uses VM_IPS hash (single source of truth) instead of hardcoded IPs
# ------------------------------------------------------------
def write_lab_hosts(vm)
  vm.vm.provision "shell",
    name: "configure-lab-hosts",
    privileged: true,
    run: "once",
    inline: render_provision("linux/lab-hosts.sh", KALI_IP: VM_IPS[:kali], DC01_IP: VM_IPS[:dc01], DB01_IP: VM_IPS[:db01], WIN10_IP: VM_IPS[:win10], LLM01_IP: VM_IPS[:llm01], LINUX01_IP: VM_IPS[:linux01], PRINT01_IP: VM_IPS[:print01], METASPLOITABLE2_IP: VM_IPS[:metasploitable2], JUICE_SHOP_IP: VM_IPS[:juice_shop], CLOUD_PENTEST_IP: VM_IPS[:cloud_pentest], CA01_ESC_IP: VM_IPS[:ca01_esc])
end

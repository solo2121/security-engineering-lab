# Windows guest helpers
# Domain controller wait, domain join, Defender, static IP, internet isolation.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def wait_for_dc(vm, ip = DC_IP, max_attempts = 60)
  vm.vm.provision "shell",
    run: "once",
    inline: render_provision("windows/wait-for-dc.ps1", MAX_ATTEMPTS: max_attempts, IP: ip)
end

def domain_join_windows(vm, vm_name, dc_ip, gateway)
  vm.vm.provision "shell",
    name: "domain-join",
    privileged: true,
    reboot: "always",
    inline: render_provision("windows/domain-join.ps1", VM_NAME: vm_name, DC_IP: dc_ip, DOMAIN_JOIN_PASS_SQ: ps_squote_escape(DOMAIN_JOIN_PASS), DOMAIN_NETBIOS: DOMAIN_NETBIOS, DOMAIN_JOIN_USER: DOMAIN_JOIN_USER, DOMAIN_NAME: DOMAIN_NAME)
end

def disable_windows_defender(vm)
  vm.vm.provision "shell",
    name: "disable-defender",
    privileged: true,
    run: "once",
    inline: render_provision("windows/disable-defender.ps1")
end

def configure_windows_static_ip(vm, ip, gateway)
  adapter_detect_ps = if PROVIDER == :libvirt
    read_provision("windows/fragments/adapter-detect-libvirt.ps1.frag").chomp
  else
    read_provision("windows/fragments/adapter-detect-virtualbox.ps1.frag").chomp
  end

  vm.vm.provision "shell",
    name: "static-ip",
    privileged: true,
    run: "once",
    inline: render_provision("windows/static-ip.ps1", IP: ip, GATEWAY: gateway, ADAPTER_DETECT: adapter_detect_ps, DC_IP: DC_IP)
end

def disable_internet_gateway(vm, vm_name)
  nat_ip_prefix = PROVIDER == :libvirt ? "192.168.121.*" : "10.0.2.*"
  vm.vm.provision "shell",
    name: "disable-mgmt-gateway-#{vm_name}",
    privileged: true,
    run: "once",
    inline: render_provision("windows/disable-internet-gateway.ps1", VM_NAME_UPPER: vm_name.upcase, NAT_IP_PREFIX: nat_ip_prefix)
end

# Windows guest helpers
# WinRM, static IP, Defender, internet isolation, domain join and health checks.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# WINDOWS COMMUNICATION - WITH TIMEOUT PARAMETER FOR FLEXIBILITY
# ------------------------------------------------------------
def configure_windows_comm(vm, user, pass, boot_timeout = 7200, winrm_timeout = 3600)
  vm.vm.communicator = "winrm"
  vm.vm.guest = :windows
  vm.vm.boot_timeout = boot_timeout

  vm.winrm.username = user
  vm.winrm.password = pass
  vm.winrm.transport = :plaintext
  vm.winrm.port = 5985
  vm.winrm.retry_limit = 240
  vm.winrm.retry_delay = 30
  vm.winrm.timeout = winrm_timeout
  vm.winrm.basic_auth_only = true

  # VirtualBox-specific Windows settings (Vagrant only applies this block
  # when actually running under the virtualbox provider)
  vm.vm.provider :virtualbox do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end
end

# ------------------------------------------------------------
# FIXED WINDOWS STATIC IP CONFIGURATION
# 5-Method adapter detection with DAD disabled and SkipAsSource=false
# ------------------------------------------------------------
def configure_windows_static_ip(vm, ip)
  # Adapter naming and the provider's NAT range differ between providers:
  # libvirt commonly surfaces the lab NIC as "Ethernet 1" with the default
  # NAT network on 192.168.121.0/24, while VirtualBox surfaces it as
  # "Ethernet"/"Ethernet 2" with NAT on 10.0.2.0/24.
  if PROVIDER == :libvirt
    adapter_detect_ps = read_provision("windows/fragments/adapter-detect-libvirt.ps1.frag")
  else
    adapter_detect_ps = read_provision("windows/fragments/adapter-detect-virtualbox.ps1.frag")
  end

  vm.vm.provision "shell",
    name: "fixed-static-ip",
    privileged: true,
    run: "once",
    inline: render_provision("windows/static-ip.ps1", IP: ip, ADAPTER_DETECT: adapter_detect_ps, DC_IP: DC_IP)
end

# ------------------------------------------------------------
# WINDOWS DEFENDER LAB BASELINE - REGISTRY ONLY APPROACH
# Uses minimal PowerShell commands (registry only) to avoid detection
# ------------------------------------------------------------
def disable_windows_defender(vm)
  vm.vm.provision "shell",
    name: "disable-defender",
    privileged: true,
    run: "once",
    inline: render_provision("windows/disable-defender.ps1")
end

# ------------------------------------------------------------
# SAFE INTERNET ISOLATION FUNCTION - WORKING VERSION FROM 1.2
# ------------------------------------------------------------
def disable_internet_gateway(vm, vm_name)
  # The NAT adapter's name/IP range differs between providers: libvirt
  # exposes it via a virtio NIC on 192.168.121.0/24, VirtualBox names it
  # "NAT"/"VirtualBox Host-Only" on 10.0.2.0/24.
  if PROVIDER == :libvirt
    nat_match_ps = read_provision("windows/fragments/nat-match-libvirt.ps1.frag", strip: true)
  else
    nat_match_ps = read_provision("windows/fragments/nat-match-virtualbox.ps1.frag", strip: true)
  end

  vm.vm.provision "shell",
    name: "disable-internet-gateway-#{vm_name}",
    privileged: true,
    run: "once",
    inline: render_provision("windows/disable-internet-gateway.ps1", VM_NAME_UPPER: vm_name.upcase, NAT_MATCH: nat_match_ps, DC_IP: DC_IP, LAB_SUBNET: LAB_SUBNET)
end

# ------------------------------------------------------------
# WAIT FOR DC FUNCTION
# ------------------------------------------------------------
def wait_for_dc(vm, ip = DC_IP, max_attempts = 60)
  vm.vm.provision "shell",
    run: "once",
    inline: render_provision("windows/wait-for-dc.ps1", MAX_ATTEMPTS: max_attempts, IP: ip)
end

# ------------------------------------------------------------
# REUSABLE DOMAIN JOIN FUNCTION - ELIMINATES DUPLICATION
# ------------------------------------------------------------
def domain_join_windows(vm, hostname, ip, memory = 2048, disk_size = 40)
  configure_network(vm, ip)
  configure_provider(vm, WINDOWS_CONFIG.merge(memory: memory, disk_size: disk_size))
  configure_windows_static_ip(vm, ip)
  disable_windows_defender(vm)
  wait_for_dc(vm)

  vm.vm.provision "shell",
    name: "domain-join-#{hostname}",
    privileged: true,
    reboot: "always",
    inline: render_provision("windows/domain-join.ps1", HOSTNAME_UPPER: hostname.upcase, DC_IP: DC_IP, DOMAIN_JOIN_PASS_SQ: ps_squote_escape(DOMAIN_JOIN_PASS), DOMAIN_NETBIOS: DOMAIN_NETBIOS, DOMAIN_JOIN_USER: DOMAIN_JOIN_USER, DOMAIN_NAME: DOMAIN_NAME, HOSTNAME: hostname)

  vm.vm.provision :reload, name: "reboot-after-domain-join-#{hostname}"
end

# ------------------------------------------------------------
# HEALTH CHECK FUNCTION
# ------------------------------------------------------------
def add_health_check(vm, hostname, check_type = :windows)
  vm.vm.provision "shell",
    name: "health-check-#{hostname}",
    privileged: true,
    run: "once",
    inline: render_provision("windows/health-check.ps1", HOSTNAME_UPPER: hostname.upcase, DC_IP: DC_IP, HOSTNAME: hostname)
end

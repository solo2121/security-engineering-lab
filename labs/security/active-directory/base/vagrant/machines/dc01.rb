# VM definition: dc01
# Loaded by the Vagrantfile, which calls define_dc01(config).

def define_dc01(config)
  # ===========================================================================
  # DOMAIN CONTROLLER (DC01) - WITH MODERN ATTACK VECTORS ADDED
  # CRITICAL: DC01 needs longer timeouts for AD promotion
  # ===========================================================================
  config.vm.define "dc01", primary: true do |vm|
    vm.vm.box = "peru/windows-server-2022-standard-x64-eval"
    vm.vm.hostname = "dc01"
    vm.vm.synced_folder ".", "/vagrant", disabled: true

    # CRITICAL: DC01 uses longer timeouts (7200) for AD promotion
    # Other VMs use default timeout (3600)
    configure_windows_comm(vm, "vagrant", "vagrant", 7200, 7200)

    configure_network(vm, VM_IPS[:dc01])
    configure_provider(vm, WINDOWS_CONFIG.merge(memory: VM_MEMORY[:dc01], disk_size: 60))
    configure_windows_static_ip(vm, VM_IPS[:dc01])
    disable_windows_defender(vm)

    vm.vm.provision "shell", name: "phase0-winrm-bootstrap", privileged: false, run: "once", inline: render_provision("dc01/phase0-winrm-bootstrap.ps1")

    vm.vm.provision "shell", name: "phase1-basic-setup", privileged: false, inline: render_provision("dc01/phase1-basic-setup.ps1")

    vm.vm.provision :reload, name: "reboot-after-phase1"

    vm.vm.provision "shell", name: "phase2-post-reboot-verification", privileged: false, inline: render_provision("dc01/phase2-post-reboot-verification.ps1")

    # ============================================================
    # PHASE 3 - AD PROMOTION - FIXED WITH EXPLICIT PARAMETERS
    # ============================================================
    vm.vm.provision "shell", name: "phase3-ad-promotion", privileged: false, inline: render_provision("dc01/phase3-ad-promotion.ps1", DOMAIN_NAME: DOMAIN_NAME, DOMAIN_NETBIOS: DOMAIN_NETBIOS)

    vm.vm.provision :reload, name: "reboot-after-ad-promotion"

    vm.vm.provision "shell", name: "phase4-winrm-stabilizer", privileged: true, inline: render_provision("dc01/phase4-winrm-stabilizer.ps1")

    # ============================================================
    # PHASE 5 - FULL DC CONFIG - WITH MODERN ATTACK VECTORS ADDED
    # FIX: Domain name hardcoded as "lab.local" for PowerShell
    # FIX: DNS records hardcoded with IP addresses
    # ============================================================
    # CHANGED: Heredoc kept as <<-'SHELL' to prevent Ruby syntax errors on reg add backslashes.
    # Using .gsub to safely inject DOMAIN_JOIN_PASS without triggering Ruby interpolation.
    vm.vm.provision "shell",
      name: "phase5-full-dc-config",
      privileged: true,
      inline: render_provision("dc01/phase5-full-dc-config.ps1", DOMAIN_JOIN_PASS_DQ: ps_dquote_escape(DOMAIN_JOIN_PASS))

    vm.vm.provision "shell", name: "phase6-cleanup", privileged: true, run: "once", inline: render_provision("dc01/phase6-cleanup.ps1")

    vm.vm.provision :reload, name: "final-reboot"
    disable_internet_gateway(vm, "dc01")
    add_health_check(vm, "dc01")
  end
end

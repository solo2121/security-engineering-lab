# DC01 provisioning
# VM-specific provisioners for DC01.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_dc01(vm)
  # DC01 specific provisioning - AD LOGIC COMPLETELY PRESERVED
  vm.vm.provision "shell", name: "dc-winrm-bootstrap", privileged: false, run: "once", inline: render_provision("dc01/phase0-winrm-bootstrap.ps1")

  vm.vm.provision "shell", name: "dc-phase1", privileged: false, run: "once", inline: render_provision("dc01/phase1-basic-setup.ps1")

  vm.vm.provision :reload, name: "dc-reboot-1"

  vm.vm.provision "shell", name: "dc-phase2", privileged: false, run: "once", inline: render_provision("dc01/phase2-post-reboot-verification.ps1")

  vm.vm.provision "shell", name: "dc-phase3", privileged: false, run: "once", inline: render_provision("dc01/phase3-ad-promotion.ps1", DOMAIN_NAME: DOMAIN_NAME, DOMAIN_NETBIOS: DOMAIN_NETBIOS)

  vm.vm.provision :reload, name: "dc-reboot-2"

  vm.vm.provision "shell", name: "dc-phase4", privileged: true, run: "once", inline: render_provision("dc01/phase4-winrm-stabilizer.ps1")

  # Phase 5: Full DC config - AD LOGIC COMPLETELY PRESERVED
  vm.vm.provision "shell", name: "dc-phase5", privileged: true, run: "once", inline: render_provision("dc01/phase5-full-dc-config.ps1", DOMAIN_JOIN_PASS_DQ: ps_dquote_escape(DOMAIN_JOIN_PASS))

  vm.vm.provision "shell", name: "dc-phase6", privileged: true, run: "once", inline: render_provision("dc01/phase6-cleanup.ps1")

  vm.vm.provision :reload, name: "dc-final-reboot"

  disable_internet_gateway(vm, "dc01")
end

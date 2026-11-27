# opnsense provisioning
# VM-specific provisioners for opnsense.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_opnsense(vm)
  vm.vm.boot_timeout = 1200

  opnsense_iface_comment = if PROVIDER == :libvirt
    "            # Interface mapping shifted by 1 to account for management NIC (vtnet0).\n" \
    "            # With mgmt_attach=true:\n" \
    "            #   vtnet0 = management (192.168.121.x — Vagrant)\n" \
    "            #   vtnet1 = WAN    (192.168.100.2)\n" \
    "            #   vtnet2 = LAN    (172.28.10.1  — VLAN 10)\n" \
    "            #   vtnet3 = OPT1   (172.28.20.1  — VLAN 20)\n" \
    "            #   vtnet4 = OPT2   (172.28.30.1  — VLAN 30)\n" \
    "            #   vtnet5 = OPT3   (172.28.40.1  — VLAN 40)\n" \
    "            #   vtnet6 = OPT4   (172.28.99.1  — VLAN 99)"
  else
    "            # VirtualBox network interfaces:\n" \
    "            #   vtnet0 = NAT (management - 10.0.2.15)\n" \
    "            #   vtnet1 = WAN    (192.168.100.2)\n" \
    "            #   vtnet2 = LAN    (172.28.10.1  — VLAN 10)\n" \
    "            #   vtnet3 = OPT1   (172.28.20.1  — VLAN 20)\n" \
    "            #   vtnet4 = OPT2   (172.28.30.1  — VLAN 30)\n" \
    "            #   vtnet5 = OPT3   (172.28.40.1  — VLAN 40)\n" \
    "            #   vtnet6 = OPT4   (172.28.99.1  — VLAN 99)"
  end

  vm.vm.provision "shell",
    name: "opnsense-init",
    run: "once",
    inline: render_provision("opnsense/init.sh", PROVIDER_UPPER: PROVIDER.to_s.upcase, OPNSENSE_IFACE_COMMENT: opnsense_iface_comment)

  vm.vm.provision :reload, name: "opnsense-reload-1"

  vm.vm.provision "shell",
    name: "opnsense-verify",
    run: "once",
    inline: render_provision("opnsense/verify.sh")

  vm.vm.provision :reload, name: "opnsense-reload-2"
end

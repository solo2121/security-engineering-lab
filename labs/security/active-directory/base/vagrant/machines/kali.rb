# VM definition: kali
# Loaded by the Vagrantfile, which calls define_kali(config).

def define_kali(config)
  # ===========================================================================
  # KALI - PROFESSIONAL PENTESTING PLATFORM WITH MODERN TOOLS
  # (defaults to Kali Linux; set KALI_BOX to use Parrot Security or
  # another Debian-based box instead - see ATTACKER BOX SELECTION above)
  # ===========================================================================
  config.vm.define "kali" do |vm|
    vm.vm.box = KALI_BOX
    vm.vm.box_version = KALI_BOX_VERSION
    vm.vm.hostname = "kali.lab.local"
    configure_network(vm, VM_IPS[:kali])

    configure_provider(vm, memory: VM_MEMORY[:kali], cpus: VM_CPUS[:kali])

    write_lab_hosts(vm)

    # Runs on EVERY "vagrant up"/"vagrant reload" (not just first boot).
    # Auto-repairs any dpkg/apt state left broken by an interrupted install
    # or a manual "apt upgrade" run inside the VM, so you never have to SSH
    # in and run `dpkg --configure -a` / `apt --fix-broken install` by hand.
    vm.vm.provision "shell", name: "kali-apt-selfheal", run: "always", inline: render_provision("kali/apt-selfheal.sh")

    vm.vm.provision "shell", name: "kali-tools", inline: render_provision("kali/tools.sh")
  end
end

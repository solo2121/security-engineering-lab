# One VM
# define_vm: network, hardware, hosts file and base provisioning, then the role.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def define_vm(config, name, cfg)
  config.vm.define name do |vm|
    vm.vm.box = cfg[:box]
    vm.vm.hostname = name

    # Provider-specific network configuration
    if PROVIDER == :libvirt
      vm.vm.network "private_network", ip: cfg[:ip]
    else
      vm.vm.network "private_network", ip: cfg[:ip]
      vm.vm.network "forwarded_port", guest: 22, host: 2200 + cfg[:ip].split('.').last.to_i, host_ip: "127.0.0.1"
    end

    # rsync is one-way (host -> guest), so copy the files the master writes in
    # /vagrant back to the host once it is up; workers pick them up when they boot.
    if PROVIDER == :libvirt && cfg[:role] == "master" && ENV['SYNC_TYPE'].to_s.empty?
      vm.trigger.after :up do |t|
        t.name = "Pull cluster handoff files from #{name} to host"
        t.ruby do |_env, machine|
          %w[.cluster_state.json .k3s_token .cluster_ready].each do |f|
            data = +""
            begin
              machine.communicate.execute("cat /vagrant/#{f} 2>/dev/null", error_check: false) do |type, out|
                data << out if type == :stdout
              end
            rescue StandardError => e
              puts "Could not read #{f} from #{name}: #{e.message}"
            end
            File.write(File.join(LAB_DIR, f), data) unless data.empty?
          end
        end
      end
    end

    # Provider-specific hardware configuration
    if PROVIDER == :libvirt
      configure_libvirt(vm, memory: cfg[:memory] || 1024, cpus: cfg[:cpus] || 1)
    else
      configure_virtualbox(vm, memory: cfg[:memory] || 1024, cpus: cfg[:cpus] || 1)
    end

    # Attach extra disks for lab VMs
    attach_disks(vm, name) if LINUX_LABS.key?(name)

    # /etc/hosts configuration
    vm.vm.provision "shell", run: "always", inline: render_provision("common/lab-hosts.sh", HOSTS_ENTRIES: HOSTS_ENTRIES)

    # Base provisioning
    vm.vm.provision "shell", inline: render_provision("common/base.sh")

    # =====================================================================
    # ROLE-SPECIFIC PROVISIONING
    # =====================================================================
    case cfg[:role]
    when "master"
      provision_master(vm, cfg)
    when "worker"
      provision_worker(vm, cfg, name)
    when "lab", "ansible"
      provision_lab(vm)
    when "kind"
      provision_kind(vm)
    when "k3d"
      provision_k3d(vm)
    when "cicd"
      provision_cicd(vm, cfg)
    end
  end
end

# Vagrant plugin checks
# Required and optional plugins. Called first inside Vagrant.configure.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def configure_plugins(config)
  # ----------------------------------------------------------------------------
  # PLUGIN CHECKS (INSIDE CONFIGURE BLOCK)
  # ----------------------------------------------------------------------------
  unless Vagrant.has_plugin?("vagrant-reload")
    raise "ERROR: vagrant-reload plugin is required. Please run: vagrant plugin install vagrant-reload"
  end

  if PROVIDER == :libvirt
    unless Vagrant.has_plugin?("vagrant-libvirt")
      raise "ERROR: vagrant-libvirt plugin is required. Please run: vagrant plugin install vagrant-libvirt"
    end
  end

  # ----------------------------------------------------------------------------
  # OPTIONAL PLUGINS (NICE TO HAVE)
  # ----------------------------------------------------------------------------
  if Vagrant.has_plugin?("vagrant-hostmanager")
    puts "[INFO] vagrant-hostmanager plugin detected - hosts will be auto-managed"
  end

  if Vagrant.has_plugin?("vagrant-vbguest")
    puts "[INFO] vagrant-vbguest plugin detected - guest additions will auto-update"
    if PROVIDER == :virtualbox
      config.vbguest.auto_update = true
      config.vbguest.no_install = false
    end
  end

  # ----------------------------------------------------------------------------
  # HOST MANAGER CONFIGURATION (if plugin is available)
  # ----------------------------------------------------------------------------
  if Vagrant.has_plugin?("vagrant-hostmanager")
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.manage_guest = true
    config.hostmanager.include_offline = true

    # Fixed: Properly define aliases as an array of strings
    config.hostmanager.aliases = {
      VM_IPS[:dc01] => ["dc01.lab.local", "dc01"],
      VM_IPS[:kali] => ["kali.lab.local", "kali"],
      VM_IPS[:db01] => ["db01.lab.local", "db01"],
      VM_IPS[:ca01_esc] => ["ca01-esc.lab.local", "ca01-esc"],
      VM_IPS[:win10] => ["win10.lab.local", "win10"],
      VM_IPS[:linux01] => ["linux01.lab.local", "linux01"],
      VM_IPS[:print01] => ["print01.lab.local", "print01"],
      VM_IPS[:llm01] => ["llm01.lab.local", "llm01"],
      VM_IPS[:metasploitable2] => ["metasploitable2.lab.local", "metasploitable2"],
      VM_IPS[:juice_shop] => ["juice-shop.lab.local", "juice-shop"],
      VM_IPS[:cloud_pentest] => ["cloud-pentest.lab.local", "cloud-pentest"]
    }
  end
end

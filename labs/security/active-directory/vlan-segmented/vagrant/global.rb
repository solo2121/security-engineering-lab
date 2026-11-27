# Global Vagrant settings
# Box update check and hostmanager aliases.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def configure_global(config)
  config.vm.box_check_update = false

  if Vagrant.has_plugin?("vagrant-hostmanager")
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.manage_guest = true
    config.hostmanager.include_offline = true
    config.hostmanager.aliases = {
      "DC01" => ["dc01.lab.local", "dc01"],
      "DB01" => ["db01.lab.local", "db01"],
      "CA01-ESC" => ["ca01-esc.lab.local", "ca01-esc"],
      "WIN10" => ["win10.lab.local", "win10"],
      "llm01" => ["llm01.lab.local", "llm01"],
      "linux01" => ["linux01.lab.local", "linux01"],
      "print01" => ["print01.lab.local", "print01"],
      "cloud-pentest" => ["cloud-pentest.lab.local", "cloud-pentest"],
      "metasploitable2" => ["metasploitable2.lab.local", "metasploitable2"],
      "juice-shop" => ["juice-shop.lab.local", "juice-shop"],
      "kali" => ["kali.lab.local", "kali"]
    }
  end
end

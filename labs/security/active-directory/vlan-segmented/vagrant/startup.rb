# Startup steps
# Fog env vars, Vagrant version, plugin install, network setup and the banner. These run at load time, in this order.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================
# Suppress fog/libvirt warnings
ENV["FOG_LIBVIRT_DEBUG"] = "false"
ENV["FOG_IGNORE_UNRECOGNIZED"] = "true"

Vagrant.require_version ">= 2.2.0"

def ensure_plugins(plugins)
  plugins.each do |plugin|
    unless Vagrant.has_plugin?(plugin)
      puts "Installing #{plugin} plugin..."
      system("vagrant plugin install #{plugin}") || raise("Failed to install #{plugin} plugin")
    end
  end
end

required_plugins = if PROVIDER == :libvirt
  ["vagrant-reload", "vagrant-libvirt", "vagrant-hostmanager"]
else
  ["vagrant-reload", "vagrant-hostmanager"]
end
ensure_plugins(required_plugins)

validate_host_requirements
ensure_provider_networks

puts "================================================================================"
puts "  ENTERPRISE AD PENETRATION TESTING LAB (#{PROVIDER.to_s.upcase})"
puts "================================================================================"
puts "  Profile: #{LAB_PROFILE} (#{PROFILES[LAB_PROFILE][:description]})"
puts "  VMs: #{PROFILES[LAB_PROFILE][:vms].join(', ')}"
total_memory = calculate_total_memory(LAB_PROFILE)
puts "  Total RAM: #{(total_memory/1024.0).round(1)}GB required"
puts "  Minimum RAM: #{PROFILES[LAB_PROFILE][:min_ram]/1024}GB"
puts "================================================================================"

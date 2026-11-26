# Provider detection
# Which provider (libvirt or VirtualBox) this run uses, and LAB_GUI.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# PROVIDER DETECTION (unified libvirt + VirtualBox Vagrantfile)
# ------------------------------------------------------------
# Checks, in Vagrant's own precedence order: CLI --provider flag,
# then VAGRANT_DEFAULT_PROVIDER, then a host-OS-based default
# (libvirt on Linux, VirtualBox elsewhere).
def current_provider
  ARGV.each_with_index do |arg, idx|
    if arg == '--provider' && ARGV[idx + 1]
      return ARGV[idx + 1].to_sym
    elsif arg =~ /\A--provider=(.+)\z/
      return Regexp.last_match(1).to_sym
    end
  end

  return ENV['VAGRANT_DEFAULT_PROVIDER'].to_sym if ENV['VAGRANT_DEFAULT_PROVIDER']

  RbConfig::CONFIG['host_os'] =~ /linux/ ? :libvirt : :virtualbox
end

PROVIDER = current_provider
puts "Provider: #{PROVIDER}"

# Set LAB_GUI=true to open a VirtualBox GUI window per VM (default: headless).
# No effect under libvirt.
LAB_GUI = ENV.fetch('LAB_GUI', 'false').downcase == 'true'

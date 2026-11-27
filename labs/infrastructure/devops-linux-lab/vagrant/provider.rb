# Provider detection
# Which provider (libvirt or VirtualBox) this run uses.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# PROVIDER DETECTION
# =============================================================================
def current_provider
  # Check command line for --provider first: Vagrant's own precedence is
  # CLI flag > VAGRANT_DEFAULT_PROVIDER > auto-detection, so this must be
  # checked before the environment variable, not after.
  #
  # Handles both accepted forms:
  #   vagrant up --provider=virtualbox   (single token, must be split)
  #   vagrant up --provider virtualbox   (two tokens)
  ARGV.each_with_index do |arg, idx|
    if arg == '--provider' && ARGV[idx + 1]
      return ARGV[idx + 1].to_sym
    elsif arg =~ /\A--provider=(.+)\z/
      return Regexp.last_match(1).to_sym
    end
  end

  if ENV['VAGRANT_DEFAULT_PROVIDER']
    return ENV['VAGRANT_DEFAULT_PROVIDER'].to_sym
  end

  # Default: libvirt on Linux, virtualbox otherwise
  if RbConfig::CONFIG['host_os'] =~ /linux/
    :libvirt
  else
    :virtualbox
  end
end

PROVIDER = current_provider
puts "Provider: #{PROVIDER}"

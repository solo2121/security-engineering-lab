# Network detection
# Libvirt or VirtualBox network, NETWORK_BASE, MASTER_IP and /tmp/lab.env.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# PROVIDER-SPECIFIC NETWORK DETECTION
# =============================================================================
# Read a libvirt network definition WITHOUT ever asking for a password.
#
# This Vagrantfile is evaluated on every Vagrant command (up, halt, status,
# ssh, ...), so anything here that needs sudo would prompt for the system
# password again each time sudo's credential cache expires (about 15 minutes).
# That is why `vagrant halt` used to ask for the password "after a while".
#
# Members of the "libvirt" group can talk to the system daemon directly, so
# no sudo is needed. "-c qemu:///system" is required: without it a normal
# user's virsh looks at the per-user session daemon and does not see the
# vagrant-libvirt network.
#
# "sudo -n" is only a fallback for hosts where the user is not yet in the
# libvirt group. It never prompts: it fails immediately and we move on to the
# default network address instead.
def virsh_net_dumpxml(name)
  [
    "virsh -c qemu:///system net-dumpxml #{name}",
    "sudo -n virsh -c qemu:///system net-dumpxml #{name}"
  ].each do |cmd|
    begin
      output = `#{cmd} 2>/dev/null </dev/null`
      return output if $?.success? && !output.empty?
    rescue => e
      puts "Warning: virsh lookup failed (#{e})"
    end
  end
  nil
end

def detect_libvirt_network
  %w[vagrant-libvirt default].each do |net_name|
    begin
      output = virsh_net_dumpxml(net_name)
      next if output.nil?

      doc = REXML::Document.new(output)
      ip_element = REXML::XPath.first(doc, "//ip")
      next unless ip_element

      network = ip_element.attribute('address').value
      prefix = ip_element.attribute('netmask').value
      prefix_length = prefix ? IPAddr.new(prefix).to_i.to_s(2).count('1') : 24
      return "#{network}/#{prefix_length}"
    rescue => e
      puts "Warning: Could not detect libvirt network '#{net_name}': #{e}"
    end
  end
  puts "Note: could not read the libvirt network (is your user in the 'libvirt' group?). " \
       "Using 192.168.121.0/24. Override with NETWORK_BASE or MASTER_IP."
  "192.168.121.0/24"
end

def detect_vbox_network
  # VirtualBox: Use 192.168.56.0/24 as default host-only network
  ENV['NETWORK_BASE'] || "192.168.56.0/24"
end

# Get provider-specific network
if PROVIDER == :libvirt
  LIBVIRT_NETWORK = detect_libvirt_network
  puts "Using libvirt network: #{LIBVIRT_NETWORK}"
  network_parts = LIBVIRT_NETWORK.split('/')
  DEFAULT_NETWORK_BASE = network_parts[0].split('.')[0..2].join('.')
else
  VBOX_NETWORK = detect_vbox_network
  puts "Using VirtualBox network: #{VBOX_NETWORK}"
  network_parts = VBOX_NETWORK.split('/')
  DEFAULT_NETWORK_BASE = network_parts[0].split('.')[0..2].join('.')
end

# =============================================================================
# ENVIRONMENT VARIABLE OVERRIDES
# =============================================================================
# Allow environment override for network base
#   export NETWORK_BASE="10.10.10"  # Uses 10.10.10.114 as master IP
#   export MASTER_IP="192.168.200.50"  # Uses specific IP for master
# =============================================================================

# When only MASTER_IP is given, derive NETWORK_BASE from it so the master and
# the workers always land on the same /24. Otherwise the workers would be
# placed on the auto-detected network and could never reach the master.
NETWORK_BASE = ENV['NETWORK_BASE'] ||
               (ENV['MASTER_IP'] ? ENV['MASTER_IP'].split('.')[0..2].join('.') : DEFAULT_NETWORK_BASE)

def vm_ip(octet)
  "#{NETWORK_BASE}.#{octet}"
end

# Allow environment override for master IP
MASTER_IP = ENV['MASTER_IP'] || vm_ip(114)

unless MASTER_IP.start_with?("#{NETWORK_BASE}.")
  abort("ERROR: MASTER_IP (#{MASTER_IP}) is not inside NETWORK_BASE (#{NETWORK_BASE}.0/24). " \
        "Workers would not be able to reach the master. Fix or unset NETWORK_BASE/MASTER_IP.")
end

puts "Network base: #{NETWORK_BASE}"
puts "Master IP: #{MASTER_IP}"
puts "To override: export NETWORK_BASE='your.network' or export MASTER_IP='your.ip'"

File.write("/tmp/lab.env", "MASTER_IP=#{MASTER_IP}\nNETWORK_BASE=#{NETWORK_BASE}\nPROVIDER=#{PROVIDER}\n")

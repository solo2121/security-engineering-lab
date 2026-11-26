# Environment, validation and resource report
# Provider environment variables, the Vagrant version check, input validation and the startup report.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# ENVIRONMENT CONFIGURATION
# ------------------------------------------------------------
if PROVIDER == :libvirt
  ENV['LIBVIRT_DEFAULT_URI'] = 'qemu:///system'
  ENV['VAGRANT_LIBVIRT_SKIP_NETWORK_VALIDATION'] = 'true'
  ENV['VAGRANT_LIBVIRT_VALIDATE_XML'] = 'false'
end
ENV['VAGRANT_WINRM_TIMEOUT'] = '3600'

Vagrant.require_version ">= 2.2.0"

# ------------------------------------------------------------------------------
# SAFE ADDITION: Top-level validation (NON-BREAKING)
# ------------------------------------------------------------------------------
raise "Invalid domain name format" unless DOMAIN_NAME =~ /\A[a-z0-9.-]+\.[a-z]{2,}\z/i
raise "Invalid DC IP address" unless DC_IP =~ /\A\d+\.\d+\.\d+\.\d+\z/
raise "Invalid subnet format" unless LAB_SUBNET =~ /\A\d+\.\d+\.\d+\.\d+\/\d{1,2}\z/

# Validate memory and CPU values are reasonable
VM_MEMORY.each do |vm_name, memory|
  if memory < 512
    puts "[WARN] VM #{vm_name} has less than 512MB RAM (#{memory}MB) - this may cause issues"
  end
  if memory > 16384
    puts "[WARN] VM #{vm_name} has more than 16GB RAM (#{memory}MB) - ensure your host can handle this"
  end
end

VM_CPUS.each do |vm_name, cpus|
  if cpus < 1
    puts "[WARN] VM #{vm_name} has invalid CPU count (#{cpus}) - defaulting to 1"
    VM_CPUS[vm_name] = 1
  end
  if cpus > 8
    puts "[WARN] VM #{vm_name} has more than 8 CPUs (#{cpus}) - this may cause performance issues"
  end
end

# LAB RESOURCE CALCULATION
# ============================================================
total_memory = VM_MEMORY.values.sum
total_gb = (total_memory / 1024.0).round(1)

puts ""
puts "=============================================================="
puts " LAB PROVISIONING REPORT"
puts "=============================================================="
puts "  Status              : RESOURCE CALCULATION COMPLETE"
puts "  VM Count            : #{VM_MEMORY.keys.count}"
puts "  Total Memory        : #{total_gb} GB"
puts "  Recommended Host    : 48 GB RAM"
puts "  Minimum Host        : 32 GB (restricted mode)"
puts ""

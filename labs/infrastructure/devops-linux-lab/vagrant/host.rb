# Host detection
# Host OS and the system resource check.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# HOST OS DETECTION
# =============================================================================
def host_os
  case RbConfig::CONFIG['host_os']
  when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
    :windows
  when /darwin|mac os/
    :macos
  when /linux/
    :linux
  else
    :unknown
  end
end

puts "Host OS detected: #{host_os}"

# =============================================================================
# SYSTEM RESOURCE CHECK
# =============================================================================
def check_system_resources
  if host_os == :linux
    total_memory = `grep MemTotal /proc/meminfo | awk '{print $2/1024}'`.to_i rescue 0
    total_cpus = `nproc`.to_i rescue 1

    if total_memory > 0 && total_memory < 8192
      puts "WARNING: System has #{total_memory}MB RAM. Full lab requires 16GB+."
      puts "         Consider using LAB_PROFILE=minimal or dev."
    end

    if total_cpus > 0 && total_cpus < 4
      puts "WARNING: System has #{total_cpus} CPU cores. Full lab requires 4+ cores."
    end
  end
end

check_system_resources

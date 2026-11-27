# Host capability detection
# RAM, CPU, KVM and disk detection and the automatic profile choice.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# HOST CAPABILITY DETECTION - WITH FALLBACKS
# ==============================================================================
def detect_total_ram_mb
  case RUBY_PLATFORM
  when /linux/
    mem_total = `grep MemTotal /proc/meminfo 2>/dev/null`.to_i / 1024
    if mem_total == 0
      mem_total = `free -m 2>/dev/null | awk '/^Mem:/ {print $2}'`.to_i
    end
    if mem_total == 0
      mem_total = 16384  # Assume 16GB as safe default
    end
    mem_total
  when /darwin/
    `sysctl -n hw.memsize`.to_i / 1024 / 1024
  when /mswin|mingw|cygwin/
    `wmic computersystem get TotalPhysicalMemory`.to_i / 1024 / 1024
  else
    16384
  end
end

def detect_cpu_cores
  case RUBY_PLATFORM
  when /linux/
    `nproc`.to_i
  when /darwin/
    `sysctl -n hw.ncpu`.to_i
  when /mswin|mingw|cygwin/
    ENV['NUMBER_OF_PROCESSORS'].to_i
  else
    4
  end
end

def detect_kvm_support
  case RUBY_PLATFORM
  when /linux/
    system("kvm-ok > /dev/null 2>&1") ||
    system("lsmod | grep kvm > /dev/null 2>&1")
  else
    false
  end
end

def detect_disk_space_mb
  case RUBY_PLATFORM
  when /linux/
    `df -BG . | tail -1 | awk '{print $4}' | sed 's/G//'`.to_i * 1024
  when /darwin/
    `df -g . | tail -1 | awk '{print $4}'`.to_i * 1024
  else
    10240
  end
end

def get_optimal_profile
  ram_mb = detect_total_ram_mb
  if ram_mb == 0
    ram_mb = 16384
  end
  if ram_mb < 20000
    'minimal'
  elsif ram_mb < 40000
    'ad'
  else
    'full'
  end
end

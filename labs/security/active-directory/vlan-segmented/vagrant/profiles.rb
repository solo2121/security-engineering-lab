# Lab profiles
# PROFILES, the LAB_PROFILE override and the auto-detect banner.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# VM PROFILES - Data-Driven
# ==============================================================================
PROFILES = {
  'minimal' => {
    description: 'Minimal lab - OPNsense, DC01, Kali only',
    vms: %w[opnsense DC01 kali],
    min_ram: 8192,
    recommended_ram: 16384
  },
  'ad' => {
    description: 'Active Directory focus - Domain Controller + Windows clients',
    vms: %w[opnsense DC01 kali WIN10 CA01-ESC DB01 linux01],
    min_ram: 16384,
    recommended_ram: 32768
  },
  'cloud' => {
    description: 'Cloud security focus - OPNsense, Kali, cloud-pentest',
    vms: %w[opnsense DC01 kali cloud-pentest],
    min_ram: 12288,
    recommended_ram: 24576
  },
  'llm' => {
    description: 'LLM security focus - OPNsense, DC01, Kali, llm01 only',
    vms: %w[opnsense DC01 kali llm01],
    min_ram: 18432,
    recommended_ram: 24576
  },
  'full' => {
    description: 'Full lab - All VMs',
    vms: %w[opnsense DC01 kali CA01-ESC DB01 WIN10 linux01 print01 llm01 cloud-pentest metasploitable2 juice-shop],
    min_ram: 32768,
    recommended_ram: 49152
  }
}

PROFILE_OVERRIDE = ENV['LAB_PROFILE'] ? ENV['LAB_PROFILE'].downcase : nil
if PROFILE_OVERRIDE && PROFILES.key?(PROFILE_OVERRIDE)
  LAB_PROFILE = PROFILE_OVERRIDE
else
  LAB_PROFILE = get_optimal_profile
  puts "================================================================================"
  puts "  AUTO-DETECTED HARDWARE:"
  puts "  RAM: #{detect_total_ram_mb}MB  |  CPU: #{detect_cpu_cores} cores"
  puts "  Disk Space: #{detect_disk_space_mb/1024}GB available"
  puts "                                                                               "
  puts "  OPTIMAL PROFILE: #{LAB_PROFILE.upcase} (#{PROFILES[LAB_PROFILE][:description]})"
  puts "                                                                               "
  puts "  To override: LAB_PROFILE=full vagrant up"
  puts "================================================================================"
end

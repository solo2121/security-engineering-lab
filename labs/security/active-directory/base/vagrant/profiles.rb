# Lab profiles
# LAB_PROFILES, the active profile and its startup banner. vagrant_manager.py parses this file.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# LAB PROFILES - controls which optional VMs get created
# ------------------------------------------------------------
# "kali" and "dc01" are always created - every profile needs an
# attacker box and a domain controller.
#
# Every other VM below is created ONLY if its name appears in the
# active profile's list. This replaces the old always-on behavior
# where "vagrant up" (no args) built all 11 VMs unconditionally.
#
# Selecting a profile:
#   LAB_PROFILE=ad vagrant up          # default if LAB_PROFILE is unset
#   LAB_PROFILE=minimal vagrant up
#   LAB_PROFILE=web vagrant up
#   LAB_PROFILE=cloud vagrant up
#   LAB_PROFILE=full vagrant up
#
# A VM that isn't in the active profile is never defined, so
# "vagrant up <name>" for that VM will fail with "machine not
# found" unless you re-run with a profile that includes it, e.g.:
#   LAB_PROFILE=full vagrant up print01
LAB_PROFILES = {
  'minimal' => %w[win10],
  'ad'      => %w[db01 ca01-esc win10 linux01],
  'web'     => %w[db01 ca01-esc win10 linux01 juice-shop],
  'cloud'   => %w[db01 ca01-esc win10 linux01 cloud-pentest],
  'llm'     => %w[llm01],
  'full'    => %w[db01 ca01-esc win10 linux01 print01 llm01 metasploitable2 juice-shop cloud-pentest]
}.freeze

DEFAULT_LAB_PROFILE = 'ad'

LAB_PROFILE = ENV.fetch('LAB_PROFILE', DEFAULT_LAB_PROFILE).downcase

unless LAB_PROFILES.key?(LAB_PROFILE)
  raise "Invalid LAB_PROFILE '#{LAB_PROFILE}'. Valid profiles: #{LAB_PROFILES.keys.join(', ')} " \
        "(unset LAB_PROFILE to use the default '#{DEFAULT_LAB_PROFILE}' profile)"
end

ACTIVE_OPTIONAL_VMS = LAB_PROFILES[LAB_PROFILE]

def profile_includes?(vm_name)
  ACTIVE_OPTIONAL_VMS.include?(vm_name)
end

puts ""
puts "=============================================================="
puts " LAB_PROFILE: #{LAB_PROFILE}"
puts "=============================================================="
puts "  Always-on : kali, dc01"
puts "  Included  : #{ACTIVE_OPTIONAL_VMS.empty? ? '(none)' : ACTIVE_OPTIONAL_VMS.join(', ')}"
puts "  Excluded  : #{(LAB_PROFILES.values.flatten.uniq - ACTIVE_OPTIONAL_VMS).join(', ')}"
puts "  To change : LAB_PROFILE=<#{LAB_PROFILES.keys.join('|')}> vagrant up"
puts "=============================================================="
puts ""

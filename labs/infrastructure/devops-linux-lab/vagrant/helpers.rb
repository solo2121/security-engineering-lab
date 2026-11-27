# Profile helpers
# should_start? and the default VM size.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
def should_start?(vm_name, profile, start_list)
  return true if start_list.include?(vm_name)
  case profile
  when 'minimal'
    vm_name == 'devops-1' || vm_name == 'worker-1'
  when 'dev'
    vm_name == 'devops-1' || vm_name == 'worker-1' ||
    vm_name == 'node1' || vm_name == 'node2'
  when 'full'
    true
  else
    vm_name == 'devops-1' || vm_name == 'worker-1'
  end
end

DEFAULT = { memory: 1024, cpus: 1 }.freeze

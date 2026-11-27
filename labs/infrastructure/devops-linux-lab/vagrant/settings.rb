# Run settings
# LAB_PROFILE, LAB_GUI, START_VMS and the other environment variables.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# =============================================================================
# CONFIGURATION
# =============================================================================
LAB_PROFILE = ENV['LAB_PROFILE'] || 'minimal'
LAB_GUI = ENV.fetch('LAB_GUI', 'false').downcase == 'true'
START_VMS = ENV['START_VMS'] ? ENV['START_VMS'].split(',') : []
FAST_BOOT = ENV['FAST_BOOT'] || 'false'
K8S_API_HOST_PORT = ENV['K8S_API_HOST_PORT'] || '16443'
DEBUG = ENV['DEBUG'] || 'false'
CACHE_MODE = ENV['CACHE_MODE'] || 'zero'

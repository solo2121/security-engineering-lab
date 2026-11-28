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
# Boxes for the Enterprise Linux practice VMs. Override to try another build,
# e.g. ROCKY_BOX=bento/rockylinux-9.6 ALMA_BOX=almalinux/9 vagrant up rocky-lab alma-lab
#
# Rocky 10: the Vagrant Cloud entry for rockylinux/10 pointed to a deleted
# libvirt image, so by default the official image is downloaded straight from
# dl.rockylinux.org (one file per provider, "latest" alias) and stored locally
# as the box "rocky10". Set ROCKY_BOX to use a registry box instead, or
# ROCKY_BOX_URL to use another image location.
ROCKY_IMAGE_BASE = 'https://dl.rockylinux.org/pub/rocky/10/images/x86_64'
ROCKY_BOX_URLS = {
  libvirt: "#{ROCKY_IMAGE_BASE}/Rocky-10-Vagrant-Libvirt.latest.x86_64.vagrant.libvirt.box",
  virtualbox: "#{ROCKY_IMAGE_BASE}/Rocky-10-Vagrant-Vbox.latest.x86_64.vagrant.virtualbox.box"
}.freeze
ROCKY_BOX = ENV['ROCKY_BOX'] || 'rocky10'
ROCKY_BOX_URL = ENV['ROCKY_BOX_URL'] || (ENV['ROCKY_BOX'] ? nil : ROCKY_BOX_URLS[PROVIDER])
ALMA_BOX = ENV['ALMA_BOX'] || 'almalinux/10'

# Credentials and debug mode
# Password constants (env overridable) and VAGRANT_DEBUG.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# PASSWORD CONSTANTS - WITH ENV OVERRIDE SUPPORT
# ------------------------------------------------------------
VAGRANT_DEFAULT_PASSWORD = ENV.fetch("VAGRANT_DEFAULT_PASSWORD", "vagrant")
VAGRANT_UPDATED_PASSWORD = ENV.fetch("VAGRANT_UPDATED_PASSWORD", "Vagrant123!")
DOMAIN_JOIN_USER = ENV.fetch("DOMAIN_JOIN_USER", "svc_join")
DOMAIN_JOIN_PASS = ENV.fetch("DOMAIN_JOIN_PASS", "JoinP@ss!")

# ------------------------------------------------------------
# DEBUG MODE
# ------------------------------------------------------------
DEBUG = ENV['VAGRANT_DEBUG'] == '1' || ENV['VAGRANT_DEBUG'] == 'true'
if DEBUG
  puts "[DEBUG] Debug mode enabled"
  ENV['VAGRANT_LOG'] = 'debug'
end

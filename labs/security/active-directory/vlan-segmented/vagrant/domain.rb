# Domain constants
# Domain name, NetBIOS name, DC IP and the DN builder.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# DOMAIN CONSTANTS
# ------------------------------------------------------------
DOMAIN_NAME = "lab.local"
DOMAIN_NETBIOS = "LAB"
DC_IP = "172.28.10.21"

def build_domain_dn(domain_name)
  domain_name.split(".").map { |part| "DC=#{part}" }.join(",")
end

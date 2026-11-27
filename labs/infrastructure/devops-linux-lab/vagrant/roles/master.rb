# Role: master
# provision_master adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_master(vm, cfg)
  # Port forwarding
  vm.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 443, host: 8443, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 6443, host: K8S_API_HOST_PORT.to_i, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 30001, host: 30001, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 30003, host: 30003, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: 30004, host: 30004, host_ip: "127.0.0.1"

  # ===================================================================
  # PROVISIONER 1: BASE LAB + K3S + HARBOR
  # ===================================================================
  vm.vm.provision "shell", inline: render_provision("master/01-base-k3s-harbor.sh", CFG_IP: cfg[:ip], HARBOR_PROJECT: HARBOR_PROJECT, HARBOR_CHART_VERSION: HARBOR_CHART_VERSION, INGRESS_NGINX_VERSION: INGRESS_NGINX_VERSION, K3S_VERSION: K3S_VERSION, DOCKER_VERSION: DOCKER_VERSION, HARBOR_PASS_ESCAPED: Shellwords.escape(HARBOR_PASSWORD), FAST_BOOT: FAST_BOOT, LAB_PROFILE: LAB_PROFILE, K8S_API_HOST_PORT: K8S_API_HOST_PORT, CACHE_MODE: CACHE_MODE, PROVIDER: PROVIDER, AIRGAP_IMAGES_LIST: AIRGAP_IMAGES.map { |image| "\"#{image}\"" }.join("\n"), HELM_VERSION: HELM_VERSION)

  # ===================================================================
  # PROVISIONER 2: ENTERPRISE TOOLS
  # ===================================================================
  vm.vm.provision "shell", inline: render_provision("master/02-enterprise-tools.sh", CFG_IP: cfg[:ip], ARGOCD_VERSION: ARGOCD_VERSION, PROMETHEUS_VERSION: PROMETHEUS_VERSION, FALCO_VERSION: FALCO_VERSION, KYVERNO_VERSION: KYVERNO_VERSION, CERT_MANAGER_VERSION: CERT_MANAGER_VERSION, TERRAFORM_VERSION: TERRAFORM_VERSION, OPENTOFU_VERSION: OPENTOFU_VERSION, FAST_BOOT: FAST_BOOT)

  # ===================================================================
  # PROVISIONER 3: DEVSECOPS ATTACK VECTORS
  # ===================================================================
  vm.vm.provision "shell", inline: render_provision("master/03-devsecops-attack-vectors.sh", CFG_IP: cfg[:ip], HARBOR_PASS_ESCAPED: Shellwords.escape(HARBOR_PASSWORD))
end

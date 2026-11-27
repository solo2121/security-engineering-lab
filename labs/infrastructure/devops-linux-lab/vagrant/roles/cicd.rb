# Role: cicd
# provision_cicd adds this role's ports and provisioners.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

def provision_cicd(vm, cfg)
  vm.vm.network "forwarded_port", guest: GITEA_PORT, host: GITEA_PORT, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: JENKINS_PORT, host: JENKINS_HOST_PORT, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: SONARQUBE_PORT, host: SONARQUBE_PORT, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: VAULT_PORT, host: VAULT_PORT, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: ZAP_PORT, host: ZAP_PORT, host_ip: "127.0.0.1"
  vm.vm.network "forwarded_port", guest: JENKINS_AGENT_PORT, host: JENKINS_AGENT_PORT, host_ip: "127.0.0.1"

  vm.vm.provision "shell", inline: render_provision("common/enable-docker.sh")

  vm.vm.provision "shell", inline: render_provision("cicd/cicd-tools.sh", CFG_IP: cfg[:ip], HARBOR_PASS_ESCAPED: Shellwords.escape(HARBOR_PASSWORD), FAST_BOOT: FAST_BOOT, GITEA_VERSION: GITEA_VERSION, JENKINS_VERSION: JENKINS_VERSION, SONARQUBE_VERSION: SONARQUBE_VERSION, VAULT_VERSION: VAULT_VERSION, ZAP_VERSION: ZAP_VERSION, GITLEAKS_VERSION: GITLEAKS_VERSION, TRIVY_VERSION: TRIVY_VERSION, GITEA_PORT: GITEA_PORT, JENKINS_PORT: JENKINS_PORT, SONARQUBE_PORT: SONARQUBE_PORT, VAULT_PORT: VAULT_PORT, ZAP_PORT: ZAP_PORT, JENKINS_AGENT_PORT: JENKINS_AGENT_PORT)
end

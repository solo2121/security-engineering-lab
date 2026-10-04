# frozen_string_literal: true

# Opt-in "advanced controls" for the Windows Server Hardening lab:
#   * Windows LAPS            (DC prepares AD + GPO; member server escrows its password)
#   * Sysmon + WEF            (Sysmon everywhere; member server is the WEF collector)
#   * Credential Guard / VBS  (member server only, separately opt-in, preflight-gated)
#
# Nothing happens unless HARDENING_ADVANCED=1 is exported on the host, so the
# existing v0.1.0 behaviour is unchanged by default.
#
# Usage from the lab Vagrantfile (see docs/advanced-controls.md):
#
#   require_relative "provision/advanced/vagrant_advanced"
#
#   config.vm.define "dc01-hardened" do |node|
#     # ... existing definition and provisioners ...
#     AdvancedControls.apply_dc(node)          # keep this LAST in the block
#   end
#
#   config.vm.define "srv01-hardened" do |node|
#     node.vm.hostname = "srv01-hardened"
#     # ... box, network, provider settings ...
#     AdvancedControls.apply_member(node)
#   end
#
# Requires the vagrant-reload plugin for the reboots between steps.

module AdvancedControls
  DIR        = File.expand_path(__dir__).freeze
  CONFIG_DIR = File.join(DIR, "config").freeze
  GUEST_DIR  = "C:/ProgramData/LabAdvanced"
  TRUTHY     = %w[1 true yes on].freeze

  module_function

  def flag?(name, env = ENV)
    TRUTHY.include?(env.fetch(name, "0").to_s.strip.downcase)
  end

  def enabled?(env = ENV)
    flag?("HARDENING_ADVANCED", env)
  end

  def credential_guard?(env = ENV)
    enabled?(env) && flag?("HARDENING_CREDENTIAL_GUARD", env)
  end

  # Values handed to the guest scripts. Secrets come from the host environment
  # and are never written to the repository.
  def guest_env(env = ENV)
    domain    = env.fetch("LAB_DOMAIN", "")
    collector = env.fetch("LAB_COLLECTOR_FQDN", domain.empty? ? "" : "srv01-hardened.#{domain}")
    {
      "LAB_DOMAIN"                => domain,
      "LAB_DC_IP"                 => env.fetch("LAB_DC_IP", ""),
      "LAB_DOMAIN_ADMIN"          => env.fetch("LAB_DOMAIN_ADMIN", "Administrator"),
      "LAB_DOMAIN_ADMIN_PASSWORD" => env.fetch("LAB_DOMAIN_ADMIN_PASSWORD", ""),
      "LAB_SERVERS_OU"            => env.fetch("LAB_SERVERS_OU", "LabServers"),
      "LAB_COLLECTOR_FQDN"        => collector,
      "SYSMON_CONFIG_SOURCE"      => env.fetch("SYSMON_CONFIG_SOURCE", "swift"),
      "SYSMON_CONFIG_SHA256"      => env.fetch("SYSMON_CONFIG_SHA256", ""),
      "HARDENING_STRICT"          => env.fetch("HARDENING_STRICT", "0")
    }
  end

  def upload_configs(vm)
    %w[sysmon-lab-baseline.xml wef-subscription.xml].each do |name|
      vm.provision "file",
                   name: "advanced: upload #{name}",
                   source: File.join(CONFIG_DIR, name),
                   destination: "#{GUEST_DIR}/#{name}"
    end
  end

  def run(vm, label, script, env)
    vm.provision "shell",
                 name: "advanced: #{label}",
                 path: File.join(DIR, script),
                 privileged: true,
                 env: env
  end

  def reload(vm)
    if Vagrant.has_plugin?("vagrant-reload")
      vm.provision :reload
    else
      warn "[advanced-controls] vagrant-reload is not installed; reboot the guest manually " \
           "(vagrant reload) for the changes to take effect."
    end
  end

  def apply_dc(vm, env = ENV)
    return unless enabled?(env)

    genv = guest_env(env)
    upload_configs(vm)
    run(vm, "Windows LAPS (schema, OU, GPO)", "02-Enable-WindowsLaps-DC.ps1", genv)
    run(vm, "Sysmon",                         "10-Install-Sysmon.ps1",        genv)
    run(vm, "WEF source",                     "12-Configure-WefSource.ps1",   genv)
    reload(vm)
  end

  def apply_member(vm, env = ENV)
    return unless enabled?(env)

    genv = guest_env(env)
    upload_configs(vm)
    run(vm, "join lab domain", "01-Join-LabDomain.ps1", genv)
    reload(vm)
    run(vm, "Windows LAPS (apply and verify)", "03-Apply-And-Verify-Laps.ps1", genv)
    run(vm, "WEF collector",                   "11-Setup-WefCollector.ps1",    genv)
    run(vm, "Sysmon",                          "10-Install-Sysmon.ps1",        genv)
    run(vm, "WEF source",                      "12-Configure-WefSource.ps1",   genv)
    run(vm, "Credential Guard (configure)",    "20-Enable-CredentialGuard.ps1", genv) if credential_guard?(env)
    reload(vm)
    run(vm, "WEF (verify)",                    "13-Test-Wef.ps1",              genv)
    run(vm, "Credential Guard (verify)",       "21-Test-CredentialGuard.ps1",  genv) if credential_guard?(env)
  end
end

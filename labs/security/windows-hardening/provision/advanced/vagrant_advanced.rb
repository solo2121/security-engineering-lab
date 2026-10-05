# frozen_string_literal: true

# Opt-in "advanced controls" for the Windows Server Hardening lab:
#   * Windows LAPS            (DC prepares AD + GPO; win-member escrows its password)
#   * Sysmon + WEF            (Sysmon everywhere; win-member is the WEF collector)
#   * Credential Guard / VBS  (win-member only, separately opt-in, preflight-gated)
#
# Nothing happens unless HARDENING_ADVANCED=1 is exported on the host, so the
# default behaviour of the lab is unchanged.
#
# The lab Vagrantfile builds a settings hash and calls (vm.vm is the machine config):
#   AdvancedControls.apply_dc(vm.vm, ADVANCED_SETTINGS)       # end of dc01-hardened
#   AdvancedControls.apply_member(vm.vm, ADVANCED_SETTINGS)   # end of win-member
#
# Required settings keys: :domain, :dc_ip, :admin_password, :collector_fqdn
# Optional: :admin (default "Administrator"), :collector (default true)

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

  # Values handed to the guest scripts. Domain details come from the Vagrantfile
  # constants; tuning knobs come from the host environment.
  def guest_env(settings, env = ENV)
    {
      "LAB_DOMAIN"                => settings.fetch(:domain).to_s,
      "LAB_DC_IP"                 => settings.fetch(:dc_ip).to_s,
      "LAB_DOMAIN_ADMIN"          => settings.fetch(:admin, "Administrator").to_s,
      "LAB_DOMAIN_ADMIN_PASSWORD" => settings.fetch(:admin_password).to_s,
      "LAB_COLLECTOR_FQDN"        => settings.fetch(:collector_fqdn).to_s,
      "LAB_SERVERS_OU"            => env.fetch("LAB_SERVERS_OU", "LabServers"),
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

  def reload(vm, label)
    vm.provision :reload, name: "advanced: reboot (#{label})"
  end

  def apply_dc(vm, settings, env = ENV)
    return unless enabled?(env)

    genv      = guest_env(settings, env)
    collector = settings.fetch(:collector, true)

    upload_configs(vm)
    run(vm, "Windows LAPS (schema, OU, GPO)", "02-Enable-WindowsLaps-DC.ps1", genv)
    run(vm, "Sysmon",                         "10-Install-Sysmon.ps1",        genv)
    if collector
      run(vm, "WEF source", "12-Configure-WefSource.ps1", genv)
    else
      puts "[advanced-controls] No WEF collector in this profile; use LAB_PROFILE=full for " \
           "forwarding and the LAPS client."
    end
    reload(vm, "dc01-hardened")
  end

  def apply_member(vm, settings, env = ENV)
    return unless enabled?(env)

    genv = guest_env(settings, env)
    upload_configs(vm)
    run(vm, "move to lab OU",                  "01-Move-To-LabOu.ps1",          genv)
    reload(vm, "win-member: new policy scope")
    run(vm, "Windows LAPS (apply and verify)", "03-Apply-And-Verify-Laps.ps1",  genv)
    run(vm, "WEF collector",                   "11-Setup-WefCollector.ps1",     genv)
    run(vm, "Sysmon",                          "10-Install-Sysmon.ps1",         genv)
    run(vm, "WEF source",                      "12-Configure-WefSource.ps1",    genv)
    run(vm, "Credential Guard (configure)",    "20-Enable-CredentialGuard.ps1", genv) if credential_guard?(env)
    reload(vm, "win-member: final")
    run(vm, "WEF (verify)",                    "13-Test-Wef.ps1",               genv)
    run(vm, "Credential Guard (verify)",       "21-Test-CredentialGuard.ps1",   genv) if credential_guard?(env)
  end
end

# Harbor admin password
# HARBOR_VMS and the password prompt. Sets HARBOR_PASSWORD.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# Only these VMs use the Harbor password: devops-1 installs Harbor and
# cicd-server logs in to it. Every other VM (Linux labs, workers, Ansible
# nodes, Kind/K3d) never needs it, so provisioning them must not prompt.
# Keep in sync with HARBOR_VMS in scripts/vagrant_manager.py.
HARBOR_VMS = %w[devops-1 cicd-server].freeze

# Returns the Harbor admin password. Prompts for it only when the command
# needs it and stdin is a terminal; otherwise uses a placeholder so the
# Vagrantfile still parses.
def resolve_harbor_password
  harbor_pass = ENV['HARBOR_PASS']

  # VM names given on the command line (everything that is not a flag or the
  # subcommand). No names means the command applies to every VM, which
  # includes the Harbor VMs.
  vm_args = ARGV.reject { |arg| arg.start_with?('-') || %w[up provision reload].include?(arg) }
  harbor_needed = vm_args.empty? || vm_args.any? { |arg| HARBOR_VMS.include?(arg) }

  if harbor_pass.nil? || harbor_pass.empty?
    if $stdin.tty? && harbor_needed && ARGV.any? { |arg| arg == 'up' || arg == 'provision' || arg == 'reload' }
      if ARGV.include?('--provision') || ARGV.include?('provision')
        puts "\n" + "="*60
        puts "  HARBOR REGISTRY PASSWORD REQUIRED"
        puts "="*60
        puts ""
        puts "Harbor container registry will be available at: https://#{MASTER_IP}:30001"
        puts "Please set an admin password for Harbor."
        puts "The password must be at least 8 characters long."
        puts ""

        begin
          print "Enter Harbor admin password: "
          password = STDIN.noecho(&:gets).chomp
          puts ""

          if password.nil? || password.empty?
            abort("ERROR: Password cannot be empty.")
          end

          if password.length < 8
            puts "WARNING: Password is less than 8 characters. This is not recommended."
            print "Continue with weak password? (y/N): "
            confirm = STDIN.gets.chomp.downcase
            unless confirm == 'y' || confirm == 'yes'
              abort("Password creation cancelled.")
            end
          end

          print "Confirm password: "
          confirm_password = STDIN.noecho(&:gets).chomp
          puts ""

          if password != confirm_password
            abort("ERROR: Passwords do not match.")
          end

          ENV['HARBOR_PASS'] = password
          harbor_pass = password
          puts "Password configured successfully."
          puts "="*60
          puts ""

        rescue Interrupt
          puts "\nPassword input cancelled."
          exit 1
        end
      else
        ENV['HARBOR_PASS'] = 'PLACEHOLDER_FOR_PARSING'
        harbor_pass = 'PLACEHOLDER_FOR_PARSING'
        puts "Note: HARBOR_PASS not set. This is fine for this command."
      end
    else
      ENV['HARBOR_PASS'] = 'PLACEHOLDER_FOR_PARSING'
      harbor_pass = 'PLACEHOLDER_FOR_PARSING'
    end
  end

  harbor_pass
end

HARBOR_PASSWORD = resolve_harbor_password

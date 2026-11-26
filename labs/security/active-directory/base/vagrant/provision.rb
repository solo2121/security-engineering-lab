# Provisioning helpers
# Domain DN builder, PowerShell escaping and the provision/ script loader.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# DYNAMIC DOMAIN DN CONSTRUCTION
# ------------------------------------------------------------
def build_domain_dn(domain_name)
  parts = domain_name.split('.')
  parts.map { |part| "DC=#{part}" }.join(',')
end

# ------------------------------------------------------------
# POWERSHELL STRING-ESCAPING HELPERS (NON-BREAKING)
# ------------------------------------------------------------
# Used when embedding secrets (e.g. DOMAIN_JOIN_PASS) into generated
# PowerShell so a quote/backtick/$ in the value can't break out of the
# surrounding string literal. No-op for values that don't need escaping,
# so default lab passwords are unaffected.
def ps_squote_escape(str)
  str.to_s.gsub("'", "''")
end

def ps_dquote_escape(str)
  str.to_s.gsub('`', '``').gsub('$', '`$').gsub('"', '`"')
end

# ------------------------------------------------------------
# PROVISIONING SCRIPT LOADER
# ------------------------------------------------------------
# The provisioning scripts live next to the Vagrantfile in provision/
# (PowerShell for Windows guests, shell for Linux guests) instead of
# inline heredocs, so they can be read, diffed and linted as ordinary
# files.
#
# A script may contain @@NAME@@ placeholders for values that are only
# known at "vagrant up" time (IP addresses, domain name, ...).
# render_provision fills them in and hands the result to Vagrant as an
# inline script, so what runs inside the guest is what the heredocs used
# to produce. It raises if a placeholder has no value or a value is never
# used, so a typo fails when the Vagrantfile loads (also under
# "vagrant validate"), not halfway through a provision.
# provision/ sits next to the Vagrantfile, one level above this file.
PROVISION_DIR = File.expand_path("../provision", __dir__).freeze

def read_provision(relative_path, strip: false)
  text = File.read(File.join(PROVISION_DIR, relative_path), encoding: "UTF-8")
  # "# shellcheck ..." lines only steer the linter; they are not sent to the guest.
  text = text.gsub(/^[ \t]*# shellcheck [^\n]*\n/, "")
  strip ? text.strip : text
end

def render_provision(relative_path, vars = {})
  used = []
  rendered = read_provision(relative_path).gsub(/@@([A-Z0-9_]+)@@/) do
    key = Regexp.last_match(1).to_sym
    raise "provision/#{relative_path}: no value given for @@#{key}@@" unless vars.key?(key)

    used << key
    # A multi-line value (a script fragment) keeps the indentation of the
    # line its placeholder sits on.
    indent = Regexp.last_match.pre_match[/[ \t]*\z/]
    vars[key].to_s.chomp.gsub("\n", "\n#{indent}")
  end

  unused = vars.keys - used
  raise "provision/#{relative_path}: unused values: #{unused.join(', ')}" unless unused.empty?

  rendered
end

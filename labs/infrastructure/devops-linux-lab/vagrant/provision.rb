# Provisioning script loader
# LAB_DIR, PROVISION_DIR and render_provision (fills @@NAME@@ placeholders).
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ------------------------------------------------------------
# PROVISIONING SCRIPT LOADER
# ------------------------------------------------------------
# The provisioning scripts live next to the Vagrantfile in provision/
# instead of inline heredocs, so they can be read, diffed and linted as
# ordinary files.
#
# A script may contain @@NAME@@ placeholders for values that are only
# known at "vagrant up" time (IP addresses, tool versions, the Harbor
# password, ...). render_provision fills them in verbatim and hands the
# result to Vagrant as an inline script, so what runs inside the guest is
# what the heredocs used to produce. It raises if a placeholder has no
# value or a value is never used, so a typo fails when the Vagrantfile
# loads (also under "vagrant validate"), not halfway through a provision.
# This file is in vagrant/; the lab directory (Vagrantfile, provision/, scripts/) is one level up.
LAB_DIR = File.expand_path("..", __dir__).freeze
PROVISION_DIR = File.join(LAB_DIR, "provision").freeze

def read_provision(relative_path)
  text = File.read(File.join(PROVISION_DIR, relative_path), encoding: "UTF-8")
  # "# shellcheck ..." lines only steer the linter; they are not sent to the guest.
  text.gsub(/^[ \t]*# shellcheck [^\n]*\n/, "")
end

def render_provision(relative_path, vars = {})
  used = []
  rendered = read_provision(relative_path).gsub(/@@([A-Z0-9_]+)@@/) do
    key = Regexp.last_match(1).to_sym
    raise "provision/#{relative_path}: no value given for @@#{key}@@" unless vars.key?(key)

    used << key
    vars[key].to_s
  end

  unused = vars.keys - used
  raise "provision/#{relative_path}: unused values: #{unused.join(', ')}" unless unused.empty?

  rendered
end

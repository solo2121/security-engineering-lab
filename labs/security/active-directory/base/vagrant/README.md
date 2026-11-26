# Lab code (`vagrant/`)

The [`Vagrantfile`](../Vagrantfile) is a short list of `require_relative` lines
followed by one `Vagrant.configure` block. The code it loads lives here.

## Load order

Each file may use what the files before it defined, so the order in the
Vagrantfile matters and is the order below.

| File | What it holds |
|---|---|
| `provider_detect.rb` | `PROVIDER` (libvirt or VirtualBox) and `LAB_GUI` |
| `constants.rb` | attacker box, domain settings, and the `VM_IPS`, `VM_MEMORY` and `VM_CPUS` tables |
| `profiles.rb` | `LAB_PROFILES`, the active profile and its startup banner |
| `settings.rb` | password constants (overridable by environment variable) and `VAGRANT_DEBUG` |
| `provision.rb` | the `provision/` script loader (`render_provision`) and PowerShell escaping |
| `environment.rb` | provider environment variables, input validation, the resource report |
| `providers.rb` | default VM settings, static-IP networking, libvirt and VirtualBox setup |
| `windows.rb` | WinRM, static IP, Defender, internet isolation, domain join, health checks |
| `linux.rb` | the `/etc/hosts` helper for Linux guests |
| `plugins.rb` | required and optional Vagrant plugin checks |
| `machines/<vm>.rb` | one VM each, as `define_<vm>(config)`; optional VMs are called only if the active profile includes them |

## Changing the lab

- **Change one VM:** edit `machines/<vm>.rb`.
- **Add a VM:** add `machines/<name>.rb` with a `define_<name>(config)` function,
  add its `require_relative` line and its call (guarded by `profile_includes?` if
  it is optional) to the Vagrantfile, add its entry to the `VM_*` tables and to
  `LAB_PROFILES`.
- **Change a profile:** edit `LAB_PROFILES` in `profiles.rb`. `scripts/vagrant_manager.py`
  reads the Vagrantfile and every file it loads from here, so it follows along.

A file in this folder that the Vagrantfile does not load, or a machine file without
its call, fails `tests/python/test_base_lab_vagrant_layout.py`.

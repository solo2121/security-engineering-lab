# Lab code (`vagrant/`)

The [`Vagrantfile`](../Vagrantfile) keeps the banner and the `Vagrant.configure`
block. The rest of the code lives here, loaded with `require_relative` in the order
below. The order matters, because a file may use constants defined by the files
before it, and some files run steps when they load (plugin install, network setup,
banner).

| File | What it holds |
|---|---|
| `../base/vagrant/provider_detect.rb` | `PROVIDER` and `LAB_GUI`. This is the base lab's file, shared so the two labs detect the provider the same way |
| `domain.rb` | `DOMAIN_NAME`, `DOMAIN_NETBIOS`, `DC_IP`, `build_domain_dn` |
| `provision.rb` | PowerShell escaping helpers, `PROVISION_DIR`, `read_provision`, `render_provision` |
| `settings.rb` | domain-join and default passwords, WinRM timeouts, WAN network constants |
| `host.rb` | RAM, CPU, KVM and disk detection, `get_optimal_profile` |
| `profiles.rb` | `PROFILES`, `LAB_PROFILE` (from `LAB_PROFILE` or auto-detected) |
| `vm_config.rb` | `VM_CONFIG`: box, size, VLAN and host number per VM |
| `network.rb` | `VLAN_CONFIG`, `WAN_VLAN`, `vlan_ip`, `generate_vlan_mac` |
| `preflight.rb` | libvirt network creation, RAM total, host requirement check |
| `startup.rb` | load-time steps: fog variables, Vagrant version, plugin install, network setup, banner |
| `providers.rb` | VLAN NICs, Linux network config, WinRM, libvirt and VirtualBox settings |
| `windows.rb` | `wait_for_dc`, `domain_join_windows`, Defender, static IP, internet isolation |
| `linux.rb` | `write_lab_hosts` |
| `global.rb` | `configure_global`: box update check and hostmanager aliases |
| `machine.rb` | `define_vm`: box, communicator, NICs and common provisioners, then the VM's own file |
| `roles/<vm>.rb` | one `provision_<vm>` function per VM (`opnsense`, `dc01`, `kali`, `ca01-esc`, `db01`, `win10`, `print01`, `llm01`, `cloud-pentest`, `juice-shop`) |

## Changing the lab

- **One VM's provisioners:** edit `roles/<vm>.rb`.
- **A VM's box, size, VLAN or IP:** edit `vm_config.rb`.
- **A VLAN subnet:** edit `network.rb` (and `scripts/generate_topology_diagram.py`, which mirrors it).
- **Add a VM:** add it to `VM_CONFIG` and to the profiles, add a `roles/<vm>.rb` with a
  `provision_<vm>` function, a `require_relative` line in the Vagrantfile and a branch in `machine.rb`.
- **Add a provisioner script:** put it under `provision/` and call `render_provision`.

## Shared with the base lab, and what is not

Only `provider_detect.rb` is shared, because it is the one piece of code that is the same in
both labs. `render_provision`, `configure_windows_comm`, `configure_windows_static_ip` and the
libvirt and VirtualBox helpers look alike but behave differently (for example the base
`render_provision` keeps the indentation of a multi-line value and this one does not), so
merging them would change what is sent to the guests. They stay separate until that is done on purpose.

`tests/python/test_vlan_lab_vagrant_layout.py` fails if a file here is not loaded or a VM has
no function.

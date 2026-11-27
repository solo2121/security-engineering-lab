# Lab code (`vagrant/`)

The [`Vagrantfile`](../Vagrantfile) keeps the banner and the `Vagrant.configure`
block. The rest of the code lives here, loaded with `require_relative` in the order
below. The order matters, because a file may use constants defined by the files
before it.

| File | What it holds |
|---|---|
| `provision.rb` | `LAB_DIR`, `PROVISION_DIR` and `render_provision` (fills `@@NAME@@` placeholders in `provision/` scripts) |
| `provider.rb` | `PROVIDER` (libvirt or VirtualBox) |
| `host.rb` | host OS detection and the RAM and CPU check |
| `network.rb` | network detection, `NETWORK_BASE`, `MASTER_IP`, and `/tmp/lab.env` |
| `settings.rb` | `LAB_PROFILE`, `LAB_GUI`, `START_VMS` and the other environment variables |
| `versions.rb` | pinned tool versions and ports |
| `harbor.rb` | `HARBOR_VMS` and `HARBOR_PASSWORD` (prompts only when the command needs it and stdin is a terminal) |
| `airgap.rb` | container images loaded into Harbor |
| `helpers.rb` | `should_start?` and the default VM size |
| `providers.rb` | libvirt and VirtualBox hardware settings and the extra lab disks |
| `cluster.rb` | the VM tables, `VMS_TO_START` and `HOSTS_ENTRIES` |
| `global.rb` | `configure_global`: synced folder, timeouts, host pre-flight check, lab environment file |
| `machine.rb` | `define_vm`: network, hardware, hosts file and base provisioning, then the role |
| `roles/<role>.rb` | one function per role (`master`, `worker`, `lab`, `kind`, `k3d`, `cicd`) with its ports and provisioners |

## Changing the lab

- **A role's ports or provisioners:** edit `roles/<role>.rb`.
- **A tool version or port:** edit `versions.rb`.
- **Add a VM:** add it to a table in `cluster.rb`; give it an existing role, or add a
  role file with a `provision_<role>` function, a `require_relative` line in the
  Vagrantfile and a branch in `machine.rb`.
- **Add a provisioner script:** put it under `provision/` and call `render_provision`.

`tests/python/test_devops_lab_vagrant_layout.py` fails if a file here is not loaded or a
role has no function.

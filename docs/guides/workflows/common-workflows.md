# Common workflows

Run these commands from the selected lab directory.

Check lab state:

```bash
vagrant status
```

Start or resume all VMs defined by the selected lab:

```bash
vagrant up
```

Start a specific VM:

```bash
vagrant up <vm-name>
```

Re-run provisioning:

```bash
vagrant provision
vagrant provision <vm-name>
```

Stop all VMs while retaining their disks and state:

```bash
vagrant halt
```

Apply changes requiring a restart:

```bash
vagrant reload
```

Create and manage snapshots:

```bash
vagrant snapshot save <snapshot-name>
vagrant snapshot list
vagrant snapshot restore <snapshot-name>
vagrant snapshot delete <snapshot-name>
```

Destroy the selected lab:

```bash
vagrant destroy -f
```

> [!WARNING]
> `vagrant destroy -f` permanently removes the selected lab VMs and can remove provider-managed disks. Vagrant snapshots are provider-dependent and are not a substitute for exporting artifacts or maintaining external backups.

For VM rebuilds, provider switching, snapshot workflows, network cleanup, and performance tuning, see:

- [Quickstart Examples](../../setup/quickstart-examples.md)
- [Vagrant Management Tutorial](../infrastructure/vagrant-management-tutorial.md)
- [Lab Reset and Cleanup](lab-reset-and-cleanup.md)
- Lab-specific documentation and security-testing guides

## Lab manager examples

The Active Directory, Segmented Active Directory, and DevOps/DevSecOps labs each include a Python-based
`vagrant_manager.py` for interactive or scripted VM management (the Windows Server Hardening Lab uses plain
`vagrant` commands). Run it from the selected lab directory:

```bash
python3 scripts/vagrant_manager.py
```

Examples:

```bash
python3 scripts/vagrant_manager.py up kali dc01
python3 scripts/vagrant_manager.py up --provider virtualbox
```

View available commands:

```bash
python3 scripts/vagrant_manager.py --help
python3 scripts/vagrant_manager.py up --help
```

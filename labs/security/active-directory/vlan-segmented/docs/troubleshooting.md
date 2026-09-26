# Troubleshooting

This document lists common issues, causes, and fixes when working with the VLAN-segmented Active Directory pentest lab.

Most problems are related to permissions, libvirt state, or host networking conflicts.

---

## 1. VLAN or Bridge Creation Fails

### Symptoms

- `RTNETLINK answers: Operation not permitted`
- `Cannot find device br-vlanXX`
- The script exits early during setup

### Causes

- The script was not run with root privileges.
- libvirt is not running.
- Conflicting bridge names already exist.

### Fix

```bash
sudo ./scripts/setup-vlans.sh
```

Verify bridges:

```bash
ip link show type bridge
```

If a bridge already exists, remove it manually before retrying.

---

## 2. libvirt Cannot Attach a VM to a Bridge

### Symptoms

- VM fails to start.
- Error: `Network not found` or `Bridge not available`

### Causes

- libvirt is not running in system mode.
- The user is not in the `libvirt` group.
- The bridge was created after libvirt started.

### Fix

```bash
sudo systemctl restart libvirtd
```

Check permissions:

```bash
groups | grep libvirt
```

Re-attach the bridges:

```bash
sudo ./scripts/attach-vms-to-vlans.sh
```

---

## 3. No Network Connectivity Between VMs

### Symptoms

- Ping fails between hosts on the same VLAN.
- ARP resolution does not complete.

### Causes

- Incorrect IP configuration.
- VM attached to the wrong bridge.
- Firewall blocking traffic.

### Fix

Validate interfaces:

```bash
ip a
```

Check bridge membership:

```bash
bridge link
```

Temporarily disable firewalls for testing:

```bash
sudo iptables -F
```

---

## 4. Unexpected Cross-VLAN Connectivity

### Symptoms

- Hosts on different VLANs can communicate without routing.

### Causes

- Bridges were accidentally connected.
- A physical interface is attached to a bridge.
- The host is acting as a router.

### Fix

Ensure bridges are isolated:

```bash
bridge vlan show
```

Disable IP forwarding:

```bash
echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward
```

---

## 5. NetworkManager Conflicts

### Symptoms

- Bridges disappear after reboot.
- VLAN interfaces reset automatically.

### Causes

- NetworkManager is managing the bridges.

### Fix

Mark bridges as unmanaged:

```bash
nmcli dev set br-vlan10 managed no
nmcli dev set br-vlan20 managed no
nmcli dev set br-vlan30 managed no
```

---

## 6. Scripts Work Once but Fail After Reboot

### Symptoms

- The lab works initially but breaks after reboot.

### Causes

- Bridges are not persistent.
- libvirt networks are not reattached.

### Fix

Re-run the setup scripts:

```bash
sudo ./scripts/setup-vlans.sh
sudo ./scripts/attach-vms-to-vlans.sh
```

Persistence can be added manually if needed.

---

## 7. Diagram Generation Fails

### Symptoms

- Mermaid file is not generated.
- Diagram output is empty.

### Causes

- Missing permissions.
- Invalid configuration values.

### Fix

Verify the config file:

```bash
cat configs/lab_config.yaml
```

Re-run:

```bash
./scripts/generate-network-diagram.sh
```

---

---

## 8. `vagrant up <vm>` Fails with "was not found configured for this Vagrant environment"

### Symptoms

```
The machine with the name '<vm>' was not found configured for
this Vagrant environment.
```

This happens for VMs like `metasploitable2`, `juice-shop`, `llm01`, `print01`, or `cloud-pentest`.

### Cause

Not a bug in the requested VM — that VM genuinely isn't defined under your active `LAB_PROFILE`. The Vagrantfile only defines the machines belonging to the current profile (see [VM Profiles](../README.md#vm-profiles)); it doesn't create every VM and mark the rest "off". Running `vagrant up <vm>` directly for an excluded VM will always fail this way, by design — that's how `LAB_PROFILE` keeps resource usage bounded to what you actually asked for.

### Fix

Either:

```bash
# Re-run with a profile that includes the VM
LAB_PROFILE=full vagrant up metasploitable2
```

or, preferably, use `scripts/vagrant_manager.py` (see [Lab Manager](../README.md#lab-manager)) instead of raw `vagrant` commands — its interactive menu shows which profile a VM needs and offers to run that one action under it, without you needing to know or type the right `LAB_PROFILE` value yourself:

```bash
python3 scripts/vagrant_manager.py
```

Do not use `scripts/vagrant-manager.sh` for this — it predates `LAB_PROFILE` and has no awareness of profiles, so it will hit this same error with no recovery path.

---

## Host Network Cleanup After `vagrant destroy`

`vagrant destroy -f` removes the VMs but does **not** undo the host-side
changes made by `scripts/setup-vlans.sh` (VLAN interfaces, bridges, and any
persistent Netplan configuration it wrote). If you destroy the lab and plan
to leave the host network as it was beforehand, remove these manually:

```bash
# List VLAN bridges created by setup-vlans.sh
ip link show type bridge

# Remove a bridge (repeat per bridge)
sudo ip link set br-vlanXX down
sudo ip link delete br-vlanXX type bridge

# If setup-vlans.sh wrote a persistent Netplan file, remove or revert it,
# then re-apply
sudo netplan apply
```

There is currently no automated teardown script for these host-level
changes — treat this as a manual step until one exists.

---

## Debug Checklist

Before opening an issue:

- [ ] libvirt is running.
- [ ] Bridges exist.
- [ ] VMs are attached to the correct bridges.
- [ ] IP addressing is correct.
- [ ] No unintended routing exists.

---

## Support Notes

This lab assumes familiarity with:

- Linux networking.
- VLAN concepts.
- libvirt internals.

Issues caused by unsupported host configurations may not be addressed.

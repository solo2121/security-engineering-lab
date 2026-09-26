# Troubleshooting Guide

Common issues and fixes for the security-engineering-lab environment. Most entries below are provider-agnostic Vagrant issues or KVM/libvirt-specific (the repository default); VirtualBox-specific issues are called out explicitly. See [Installation Guide](installation.md) for full provider setup.

## How to use this guide

If something fails:
1. Find the symptom that matches your error.
2. Apply the fix in order.
3. Re-run the command or restart the lab.
4. If the issue remains, check the logs and rebuild if needed.

---

## Installation Issues

### Vagrant not found

**Problem:** `command not found: vagrant`

**Fix:**
1. Verify it is installed:
   ```bash
   which vagrant
   vagrant --version
   ```
2. If missing, install Vagrant:
   ```bash
   wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update
   sudo apt install -y vagrant
   ```

### Vagrant exits with code 1

**Problem:** `vagrant command failed with error code 1`

**Fix:**
1. Check the version:
   ```bash
   vagrant --version
   ```
2. Update Vagrant:
   ```bash
   sudo apt update
   sudo apt install --only-upgrade -y vagrant
   ```

### Libvirt service will not start (KVM/libvirt)

**Problem:** `Failed to start libvirtd service`

**Fix:**
1. Check service status:
   ```bash
   systemctl status libvirtd
   ```
2. Restart the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart libvirtd
   sudo systemctl enable libvirtd
   ```
3. Check for virtualization conflicts only if needed.

### Libvirt permission denied (KVM/libvirt)

**Problem:** `Permission denied` when running libvirt commands

**Fix:**
1. Add your user to the libvirt group:
   ```bash
   sudo usermod -aG libvirt $USER
   ```
2. Log out and back in, or refresh group membership:
   ```bash
   newgrp libvirt
   ```
3. Verify access:
   ```bash
   virsh list --all
   ```

### VirtualBox kernel module fails to load (VirtualBox, Linux hosts)

**Problem:** `vagrant up` fails with a message that the VirtualBox kernel driver is not loaded, or `VBoxManage` commands fail with a kernel-module error.

**Fix:**
1. Load the module:
   ```bash
   sudo modprobe vboxdrv
   ```
2. If it's missing after a kernel upgrade, reinstall the DKMS package so it rebuilds:
   ```bash
   sudo dpkg-reconfigure virtualbox-dkms   # Debian/Ubuntu
   ```
3. Confirm VirtualBox can now enumerate the module:
   ```bash
   VBoxManage --version
   ```

### VirtualBox and KVM/libvirt conflict on the same host (VirtualBox)

**Problem:** VirtualBox VMs fail to start (or hang) on a Linux host that also has KVM/libvirt installed and running, because both hypervisors want exclusive access to hardware virtualization extensions.

**Fix:**
1. Stop libvirt-managed VMs before starting VirtualBox VMs, or vice versa:
   ```bash
   virsh list --all
   virsh shutdown <domain>
   ```
2. If conflicts persist, run only one provider's daemon at a time (`sudo systemctl stop libvirtd` before starting VirtualBox), or use separate host sessions/profiles for each provider.

### Ansible missing dependencies

**Problem:** Python module or dependency not found

**Fix:**
1. Install Python tooling:
   ```bash
   sudo apt install -y python3-pip python3-venv
   ```
2. Install Ansible:
   ```bash
   pip3 install --user --upgrade ansible
   ```
3. Verify:
   ```bash
   ansible --version
   ```

---

## Lab Startup Issues

### `vagrant up` hangs or fails

**Problem:** `vagrant up` fails during startup

**Fix:**
1. Run with debug output:
   ```bash
   VAGRANT_LOG=debug vagrant up
   ```
2. Check the box list:
   ```bash
   vagrant box list
   ```
3. Re-download the box if needed:
   ```bash
   vagrant box add <box-name>
   ```
4. Try again without parallel provisioning:
   ```bash
   VAGRANT_NO_PARALLEL=1 vagrant up --no-parallel
   ```

### No space left on device

**Problem:** `No space left on device`

**Fix:**
1. Check disk usage:
   ```bash
   df -h
   ```
2. Clean unused boxes:
   ```bash
   vagrant box prune
   ```
3. Remove old Vagrant machine state only if necessary:
   ```bash
   rm -rf .vagrant/
   ```

### Network timeout during provisioning

**Problem:** Provisioning times out

**Fix:**
1. Verify connectivity:
   ```bash
   ping -c 4 8.8.8.8
   ```
2. Re-run provisioning:
   ```bash
   vagrant provision
   ```
3. If needed, increase timeout values in the Vagrantfile or provisioning scripts.

### VM fails to boot

**Problem:** A VM does not start correctly

**Fix:**
1. Check status:
   ```bash
   vagrant status

   # KVM/libvirt
   virsh list --all

   # VirtualBox
   VBoxManage list vms
   ```
2. Destroy and recreate:
   ```bash
   vagrant destroy -f
   vagrant up
   ```

### VM stuck provisioning

**Problem:** VM remains stuck during provisioning

**Fix:**
1. Halt the VM:
   ```bash
   vagrant halt
   ```
2. Check logs:
   ```bash
   vagrant up --debug
   ```
3. Resume provisioning:
   ```bash
   vagrant provision
   ```

---

## Network Issues

### VMs have no internet access

**Problem:** Virtual machines cannot reach the internet

**Fix (KVM/libvirt):**
1. Check libvirt networks:
   ```bash
   virsh net-list --all
   virsh net-info default
   ```
2. Restart the default network:
   ```bash
   sudo systemctl restart libvirtd
   virsh net-destroy default
   virsh net-start default
   ```
3. Check host routing:
   ```bash
   ip route
   ```

**Fix (VirtualBox):**
1. Check the VM's network adapters and the host-only network:
   ```bash
   VBoxManage showvminfo <vm-name> --machinereadable | grep ^nic
   VBoxManage list hostonlyifs
   ```
2. Recreate the host-only adapter if it's missing or misconfigured:
   ```bash
   VBoxManage hostonlyif create
   VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
   ```
3. Check host routing:
   ```bash
   ip route
   ```

### VMs cannot reach each other

**Problem:** Internal VM-to-VM communication fails

**Fix:**
1. Check IP configuration:
   ```bash
   ip addr show
   ```
2. Test connectivity:
   ```bash
   ping <other-vm-ip>
   ```
3. Review firewall rules:
   ```bash
   sudo ufw status
   sudo iptables -L -n
   ```

### Hostname resolution fails

**Problem:** Hostnames do not resolve

**Fix:**
1. Check DNS configuration:
   ```bash
   cat /etc/resolv.conf
   ```
2. If required, set DNS temporarily:
   ```bash
   echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
   ```
3. Restart the resolver if your distro uses it:
   ```bash
   sudo systemctl restart systemd-resolved
   ```

---

## Provisioning Issues

### SSH connection fails

**Problem:** `Failed to connect to host via SSH`

**Fix:**
1. Export SSH config:
   ```bash
   vagrant ssh-config > ssh_config
   ```
2. Test connection:
   ```bash
   ssh -F ssh_config vagrant@<vm-name>
   ```
3. Restart the VM:
   ```bash
   vagrant reload
   ```

### Ansible syntax error

**Problem:** Playbook syntax error

**Fix:**
1. Check syntax:
   ```bash
   ansible-playbook --syntax-check <playbook>.yml
   ```
2. Run with verbose output:
   ```bash
   ansible-playbook -vvv <playbook>.yml
   ```

### Script permission denied

**Problem:** Script will not run

**Fix:**
1. Make it executable:
   ```bash
   chmod +x script.sh
   ```
2. Run it with bash:
   ```bash
   bash script.sh
   ```

### Script command not found

**Problem:** A script fails with `command not found`

**Fix:**
1. Confirm the tool exists:
   ```bash
   which <command>
   ```
2. Install the missing package:
   ```bash
   sudo apt update
   sudo apt install -y <package>
   ```

---

## Resource Issues

### Out of memory

**Problem:** VM or host memory errors

**Fix:**
1. Check memory usage:
   ```bash
   free -h
   ```
2. Lower VM memory in the Vagrantfile.
3. Add swap if needed:
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### High CPU usage

**Problem:** Host CPU usage is too high

**Fix:**
1. Monitor usage:
   ```bash
   top
   htop
   ```
2. Suspend nonessential VMs:
   ```bash
   vagrant suspend <vm-name>
   ```

### Disk space issues

**Problem:** Storage is running out

**Fix:**
1. Check disk usage:
   ```bash
   df -h
   du -sh *
   ```
2. Prune boxes:
   ```bash
   vagrant box prune
   ```
3. Review libvirt storage pools if needed:
   ```bash
   virsh pool-list --all
   ```

---

## Performance Issues

### Slow VM performance

**Problem:** VMs respond slowly

**Fix:**
1. Check system load:
   ```bash
   htop
   ```
2. Prefer SSD storage.
3. Reduce RAM and CPU overcommit.
4. Use efficient synced-folder settings when needed.

### Slow network performance

**Problem:** Network is sluggish

**Fix:**
1. Check the host network.
2. Avoid unnecessary virtual adapters.
3. Prefer wired networking for the host if possible.

---

## Debugging

### Enable debug logging

```bash
VAGRANT_LOG=debug vagrant up
ansible-playbook -vvv playbook.yml

# KVM/libvirt
export LIBVIRT_LOG_OUTPUTS="1:stderr"
virsh list --all

# VirtualBox
VBoxManage list vms
VBoxManage showvminfo <vm-name>
```

### Check system logs

```bash
sudo journalctl -xe
sudo dmesg | tail -n 50
sudo tail -f /var/log/syslog
```

### Access a VM console

```bash
virsh console <vm-name>
```

Exit with:
```bash
Ctrl+]
```

---

## Recovery Steps

If the lab is badly broken, use this order:

1. Halt the environment.
   ```bash
   vagrant halt
   ```
2. Destroy the environment.
   ```bash
   vagrant destroy -f
   ```
3. Remove stale state if needed.
   ```bash
   rm -rf .vagrant/
   ```
4. Recreate the lab.
   ```bash
   vagrant up
   ```

---

## Getting Help

When reporting an issue, include:
- The exact error message.
- The command you ran.
- Your host OS and version.
- Which provider you're using (KVM/libvirt or VirtualBox).
- `vagrant --version`
- `virsh --version` (KVM/libvirt) or `VBoxManage --version` (VirtualBox)
- Relevant logs.

---

## Related Files

- [Installation Guide](installation.md)
- [README](README.md)
- [Architecture Design](../architecture/architecture.md)
- [Security Scope](../security-scope.md)

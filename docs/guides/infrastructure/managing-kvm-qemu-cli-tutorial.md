
---

# **The Ultimate KVM/QEMU Command Line Tutorial**

KVM (Kernel-based Virtual Machine) combined with QEMU (Quick Emulator) is a powerful, high-performance virtualization solution for Linux. This tutorial provides a complete guide to installing, configuring, and managing a full KVM/QEMU virtualization stack entirely from the command line.

---

## Table of Contents

1.  [Prerequisites & Installation](#1-prerequisites--installation)
2.  [Network Configuration (Bridge)](#2-network-configuration-bridge)
3.  [Storage Configuration](#3-storage-configuration)
4.  [Managing Virtual Machines (VMs)](#4-managing-virtual-machines-vms)
5.  [Managing Disk Images (qemu-img)](#5-managing-disk-images-qemu-img)
6.  [Expanding a VM's Disk](#6-expanding-a-vms-disk)
7.  [Snapshot Management](#7-snapshot-management)
8.  [Monitoring and Performance](#8-monitoring-and-performance)

---

## **1. Prerequisites & Installation**

### **A. Verify Virtualization Support**

First, ensure your processor supports hardware virtualization.

```bash
lscpu | grep Virtualization
```

You should see either `VT-x` (Intel) or `AMD-V` (AMD). A non-zero output from the next command also confirms support.

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

> [!SUCCESS] Expected Output
> Any value **greater than 0** confirms virtualization support. If you get `0`, check your BIOS/UEFI settings, as virtualization may be disabled.

### **B. Install Required Packages**

Update your system, then install the full virtualization stack.

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virtinst \
  virt-top \
  libguestfs-tools \
  libosinfo-bin \
  qemu-system \
  tuned
```

### **C. Enable Services and Performance Tuning**

Enable the core `libvirtd` service and `tuned` for performance optimization.

```bash
sudo systemctl enable --now libvirtd
sudo systemctl enable --now tuned
```

Apply the `virtual-host` profile, which optimizes kernel settings for running guest VMs.

```bash
sudo tuned-adm profile virtual-host
sudo tuned-adm active
```

### **D. Configure User Permissions**

To manage VMs as a non-root user, add your user to the `libvirt` and `kvm` groups.

```bash
sudo usermod -aG libvirt,kvm $(whoami)
```

> [!IMPORTANT]
> A **reboot** or logging out and back in is required for group changes to take full effect. Alternatively, you can run `newgrp libvirt` in your current shell to apply the new group temporarily.

---

## **2. Network Configuration (Bridge)**

A bridge network (`br0`) allows VMs to appear as peers on your physical network, receiving their own IP addresses from your router. This is ideal for most lab setups.

**Step 1 — Find your physical interface name**

```bash
ip -brief link show
```

Look for your primary ethernet or Wi-Fi interface (e.g., `enp3s0`, `eth0`, `wlp2s0`).

**Step 2 — Create the bridge** (using `nmcli`)

```bash
sudo nmcli connection add type bridge con-name br0 ifname br0
```

**Step 3 — Attach your physical interface** (replace `enp3s0` with your interface name)

```bash
sudo nmcli connection add type ethernet slave-type bridge con-name "KVM Bridge Slave" ifname enp3s0 master br0
```

**Step 4 — Bring the bridge up**

```bash
sudo nmcli connection up br0
```

> [!WARNING]
> Your network connection may briefly drop when you bring the bridge up. This is normal.

**Step 5 — Verify the bridge has an IP**

```bash
ip -brief addr show br0
```

---

## **3. Storage Configuration**

### **A. Set Permissions for VM Storage Directory**

The default VM image storage is `/var/lib/libvirt/images`. Grant your user read/write access using ACLs (Access Control Lists).

```bash
sudo setfacl -R -m u:$(whoami):rwX /var/lib/libvirt/images
sudo setfacl -m d:u:$(whoami):rwx /var/lib/libvirt/images
```

### **B. Manage Storage Pools**

```bash
# List all storage pools
virsh pool-list --all

# If the 'default' pool is missing or inactive, create and start it
virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
virsh pool-start default
virsh pool-autostart default
```

---

## **4. Managing Virtual Machines (VMs)**

### **A. Creating a New VM with `virt-install`**

**Example 1: Install from a local ISO file**

```bash
virt-install \
  --name ubuntu-vm \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ubuntu-vm.qcow2,size=20 \
  --os-variant ubuntu22.04 \
  --network bridge=br0 \
  --graphics none \
  --console pty,target_type=serial \
  --cdrom /path/to/ubuntu-22.04.iso
```

**Example 2: Install from a network URL (for servers)**

```bash
virt-install \
  --name ubuntu-server \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ubuntu-server.qcow2,size=20 \
  --os-variant ubuntu22.04 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --location 'http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/' \
  --extra-args 'console=ttyS0,115200n8 serial'
```

> [!TIP] Finding OS Variants
> To see a list of optimized OS profiles, run: `osinfo-query os`

### **B. Essential `virsh` Commands**

```bash
# List all VMs (running and stopped)
virsh list --all

# Start a VM
virsh start ubuntu-vm

# Graceful shutdown (requires guest agent)
virsh shutdown ubuntu-vm

# Force stop (pulling the plug)
virsh destroy ubuntu-vm

# Reboot
virsh reboot ubuntu-vm

# Connect to the serial console
virsh console ubuntu-vm
# (Exit with Ctrl + ])

# Edit a VM's XML configuration
virsh edit ubuntu-vm

# Clone a VM
virt-clone \
  --original ubuntu-vm \
  --name ubuntu-vm-clone \
  --file /var/lib/libvirt/images/ubuntu-vm-clone.qcow2

# Delete a VM and its storage
virsh undefine ubuntu-vm --remove-all-storage
```

### **C. QEMU Guest Agent**

The guest agent enables better host-guest integration (graceful shutdown, IP reporting).

**Inside the guest VM**, install and enable the agent:
```bash
sudo apt update && sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

**On the host**, you can now get the VM's IP address:
```bash
virsh domifaddr ubuntu-vm --source agent
```

---

## **5. Managing Disk Images (`qemu-img`)**

QCOW2 is the recommended format for KVM, supporting snapshots and thin provisioning.

### **A. Creating a Disk Image**

```bash
qemu-img create -f qcow2 /var/lib/libvirt/images/new-disk.qcow2 20G
```

### **B. Converting Other Formats to QCOW2**

Use `qemu-img convert` to change formats. The `-c` flag enables compression, and `-p` shows progress.

```bash
# Convert VMDK (from VMware) to QCOW2
qemu-img convert -c -p -O qcow2 source-disk.vmdk target-disk.qcow2

# Convert VHD (from Hyper-V) to QCOW2
qemu-img convert -c -p -O qcow2 source-disk.vhd target-disk.qcow2
```

### **C. Inspecting a Disk Image**

```bash
qemu-img info /var/lib/libvirt/images/ubuntu-vm.qcow2
```

Look for `file format: qcow2` and compare `virtual size` (what the guest sees) to `disk size` (actual space used on host).

---

## **6. Expanding a VM's Disk**

This three-stage process lets you increase a VM's storage when it runs out of space.

### **Step 1: Expand the QCOW2 File (on Host)**

**Shut down the VM first!**
```bash
virsh shutdown ubuntu-vm
```

Resize the image file. This example adds 20GB of capacity.
```bash
qemu-img resize /var/lib/libvirt/images/ubuntu-vm.qcow2 +20G
```

### **Step 2: Expand the Partition (in Guest)**

Start the VM and connect to its console.
```bash
virsh start ubuntu-vm
virsh console ubuntu-vm
```

Inside the VM, use `growpart` to expand the partition. (e.g., partition 1 on disk `vda`).
```bash
# If missing, run: sudo apt install cloud-guest-utils
sudo growpart /dev/vda 1
```

### **Step 3: Expand the Filesystem (in Guest)**

Finally, tell the filesystem to use the new space. The command depends on the filesystem type (`df -T /`).

**For ext4 filesystems:**
```bash
sudo resize2fs /dev/vda1
```

**For XFS filesystems:**
```bash
sudo xfs_growfs /
```

Verify the new space is available:
```bash
df -h /
```

---

## **7. Snapshot Management**

Snapshots let you save and restore the state of a VM.

```bash
# Create a snapshot
virsh snapshot-create-as ubuntu-vm --name "clean-install"

# List snapshots for a VM
virsh snapshot-list ubuntu-vm

# Revert to a snapshot
virsh snapshot-revert ubuntu-vm --snapshotname "clean-install"

# Delete a snapshot
virsh snapshot-delete ubuntu-vm --snapshotname "clean-install"
```

---

## **8. Monitoring and Performance**

```bash
# Live monitoring of all running VMs
virt-top

# Get detailed stats for a specific VM
virsh domstats ubuntu-vm

# Get general information about a VM
virsh dominfo ubuntu-vm
```

---

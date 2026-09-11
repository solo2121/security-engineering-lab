# Installation Guide

This guide provides comprehensive instructions for setting up a host to deploy the lab environments in this repository. The labs are provisioned using Vagrant and support two providers:

- **KVM/libvirt** (default, Linux hosts only) — the environment each lab is developed and tested against, with the best performance for nested virtualization.
- **VirtualBox** (cross-platform: Linux, macOS, Windows) — for hosts without KVM/libvirt, or non-Linux hosts. VirtualBox itself is Intel/AMD (x86_64) only and does not run on Apple Silicon/ARM.

Each lab includes a Vagrantfile for both providers: the KVM/libvirt Vagrantfile at the lab root, and a VirtualBox Vagrantfile under `<lab-path>/virtualbox/`. Pick the section below that matches your host.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Host System Setup (KVM/libvirt)](#step-1-host-system-setup-kvmlibvirt)
- [Step 1 (Alternative): Host System Setup (VirtualBox)](#step-1-alternative-host-system-setup-virtualbox)
- [Install Vagrant Plugins](#install-vagrant-plugins)
- [Lab 1: Active Directory Pentest Lab](#lab-1-active-directory-pentest-lab)
- [Lab 2: DevOps / DevSecOps Lab](#lab-2-devops--devsecops-lab)
- [Verification Checklist](#verification-checklist)
- [Uninstall and Cleanup](#uninstall-and-cleanup)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Automated Prerequisite Check

Before proceeding, run the `check-prerequisites.sh` script from the repository root. It validates your system's configuration for KVM, libvirt, Vagrant, required plugins, and resource availability without making any changes.

```bash
# First, clone the repository if you haven't already
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab

# Run the check
./scripts/check-prerequisites.sh --all
```

It won't install anything for you, but every failure includes the exact
fix command.

### Host requirements

- Linux host recommended.
- Hardware virtualization enabled in BIOS/UEFI.
- Sufficient CPU, RAM, and disk space for your chosen lab.
- Internet access for package installation and box downloads.

### Recommended host resources

Actual requirements depend on which lab you deploy, how many VMs you start
simultaneously, and which profile (where supported) you select. The figures
below are pulled directly from each lab's own documentation and Vagrantfile,
not estimated:

| Lab | Minimum tested | Recommended (full lab) | Disk |
|---|---|---|---|
| AD Pentest Lab (`labs/security/active-directory/base`) | ~20 GiB RAM for the documented 6-VM startup subset | 32 GB+ RAM for all 11 VMs (~29.5 GiB allocated) | 40 GiB+ for a single-lab subset |
| AD Pentest VLAN Lab (`labs/security/active-directory/vlan-segmented`) | 8 GB+ RAM (`minimal` profile, ~10 GB allocated) | 32 GB+ RAM (`full` profile, all 12 VMs, ~36 GB allocated) | 80 GB+ |
| DevOps/DevSecOps Lab (`labs/infrastructure/devops-linux-lab`) | ~10 GiB RAM (`minimal` profile) | ~30 GiB RAM (`full` profile, every VM) | 40 GiB+ for a single-lab subset |

- **CPU**: hardware virtualization (VT-x/AMD-V) must be enabled in BIOS/UEFI regardless of lab or profile.
- **Run one lab at a time** on a resource-constrained host — each lab uses its own private network, but they still compete for the same host CPU/RAM/disk.
- **Disk, combined**: budget 100 GiB+ if you plan to run full profiles or keep more than one lab's VMs on disk at the same time, even if not running concurrently.
- The DevOps/DevSecOps Lab and the AD Pentest VLAN Lab both support a `LAB_PROFILE` environment variable (e.g. `LAB_PROFILE=minimal vagrant up`) to start a reduced VM subset instead of the full lab.

For the full VM-by-VM memory breakdown, every profile's VM list, and other
tested reduced-footprint options, see
[`docs/guides/optimization/minimal-resource-deployment.md`](../guides/optimization/minimal-resource-deployment.md).

### Required tools

Common to both providers:

- Vagrant.
- Required Vagrant plugins.

KVM/libvirt provider (Linux hosts only):

- KVM/QEMU.
- Libvirt.
- Virt-Manager.
- `vagrant-libvirt` plugin.

VirtualBox provider (Linux, macOS, Windows):

- Oracle VirtualBox (6.1+ recommended).
- `vagrant-vbguest` plugin (optional, keeps Guest Additions in sync).

### Recommended Linux distros

The labs should work best on Debian-based or Fedora/RHEL-based Linux hosts. Libvirt/KVM support is Linux-specific; VirtualBox is available on all three major desktop operating systems.

### Choosing a provider

- Use **KVM/libvirt** if you're on Linux and want the best performance — this is the environment each lab is developed and tested against.
- Use **VirtualBox** if you're on macOS or Windows, or on a Linux host where libvirt/KVM isn't available (e.g., inside another VM without nested virtualization, or a locked-down environment).
- You can set your preferred provider for the session so you don't need to pass `--provider` on every command:
  ```bash
  export VAGRANT_DEFAULT_PROVIDER=virtualbox   # or: libvirt
  ```

---

## Step 1: Host System Setup (KVM/libvirt)

### 1. Update your system

```bash
sudo apt update
sudo apt upgrade -y
```

### 2. Install Vagrant

#### Debian / Ubuntu

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y vagrant
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf -y install vagrant
```

### 3. Install virtualization packages

#### Debian / Ubuntu

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virt-manager
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y @virtualization virt-manager
```

### 4. Enable and start Libvirt

#### Debian / Ubuntu

```bash
sudo systemctl enable --now libvirtd
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo systemctl enable --now libvirtd
```

### 5. Add your user to the libvirt group

```bash
sudo usermod -aG libvirt $USER
newgrp libvirt
```

### 6. Verify KVM is available

```bash
lsmod | grep kvm
```

If KVM modules are loaded, your host is ready for virtualization.

---

## Step 1 (Alternative): Host System Setup (VirtualBox)

Use this section instead of the KVM/libvirt steps above if you're on macOS, Windows, or a Linux host without libvirt.

### 1. Install VirtualBox

#### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y virtualbox
```

Alternatively, install the latest release from the [official VirtualBox downloads page](https://www.virtualbox.org/wiki/Downloads).

#### macOS

Download and install the macOS `.dmg` from the [official VirtualBox downloads page](https://www.virtualbox.org/wiki/Downloads), or via Homebrew:

```bash
brew install --cask virtualbox
```

#### Windows

Download and run the Windows installer from the [official VirtualBox downloads page](https://www.virtualbox.org/wiki/Downloads).

### 2. Install Vagrant

Install Vagrant for your platform from the [official Vagrant downloads page](https://developer.hashicorp.com/vagrant/downloads), or use the Debian/Ubuntu commands in [Install Vagrant](#2-install-vagrant) above.

### 3. Verify VirtualBox is available

```bash
VBoxManage --version
```

VirtualBox 6.1 or later is recommended. If the command isn't found, confirm VirtualBox installed correctly and that `VBoxManage` is on your `PATH`.

### 4. Enable hardware virtualization

Confirm VT-x/AMD-V is enabled in your host's BIOS/UEFI. This is required for VirtualBox and for nested virtualization used by the DevOps/DevSecOps lab's Kubernetes workloads.

---

## Install Vagrant Plugins

Install the plugins required by your chosen provider before starting the labs.

### KVM/libvirt plugins

```bash
vagrant plugin install vagrant-libvirt
```

### VirtualBox plugins

```bash
vagrant plugin install vagrant-vbguest
```

`vagrant-vbguest` keeps VirtualBox Guest Additions in sync with the guest kernel; it's optional but recommended.

### Lab 1 plugins (both providers)

For the Active Directory Pentest Lab, install the additional plugins used by Windows and reload workflows:

```bash
vagrant plugin install vagrant-reload
vagrant plugin install vagrant-winrm
```

---

## Lab 1: Active Directory Pentest Lab

This lab is located in:

```text
labs/security/active-directory/base/
```

An alternate VLAN-segmented edition is located in:

```text
labs/security/active-directory/vlan-segmented/
```

This environment includes Windows Server 2022, domain-joined workstations, AD CS, Kali Linux, LocalStack, and additional research targets.

> **Windows licensing note:** The Windows Server and Windows 10 boxes used in this lab are built from Microsoft's free [Windows Server Evaluation](https://www.microsoft.com/evalcenter/evaluate-windows-server-2022) and [Windows 10/11 Evaluation](https://developer.microsoft.com/windows/downloads/virtual-machines/) media, intended for evaluation, testing, and development use. Evaluation media is time-limited (commonly 180 days for Windows Server) and is not licensed for production use. You are responsible for complying with Microsoft's licensing terms if you use this lab beyond evaluation purposes.

### Install Lab 1 dependencies

**KVM/libvirt:**

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager vagrant
vagrant plugin install vagrant-libvirt
vagrant plugin install vagrant-reload
vagrant plugin install vagrant-winrm
```

**VirtualBox:**

```bash
sudo apt update
sudo apt install -y virtualbox vagrant   # or install VirtualBox/Vagrant per your OS (see Step 1 Alternative)
vagrant plugin install vagrant-vbguest
vagrant plugin install vagrant-reload
vagrant plugin install vagrant-winrm
```

### Clone the repository

```bash
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab/labs/security/active-directory/base
```

### Start the lab

Start the Domain Controller first, then deploy the rest of the environment.

**KVM/libvirt** (from the lab root):

```bash
vagrant up dc01
vagrant status
vagrant up
```

**VirtualBox** (from the same lab directory, no subdirectory needed):

```bash
vagrant up dc01 --provider=virtualbox
vagrant status
vagrant up --provider=virtualbox
```

### VLAN edition

If you want the segmented network edition, use:

```bash
cd ../vlan-segmented
vagrant up dc01                          # KVM/libvirt
vagrant up
# or, for VirtualBox:
vagrant up dc01 --provider=virtualbox
vagrant up --provider=virtualbox
```

### Verify Lab 1

After deployment, verify the virtual machines are running and the domain controller is reachable.

```bash
vagrant status
```

You should see the lab machines in a running state.

---

## Lab 2: DevOps / DevSecOps Lab

This lab is located in:

```text
labs/infrastructure/devops-linux-lab/
```

It includes k3s, Kind, K3d, Harbor, Argo CD, Prometheus, Grafana, Loki, Falco, Kyverno, Cert-Manager, Terraform, OpenTofu, and Ansible.

### Install Lab 2 dependencies

**KVM/libvirt:**

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager vagrant
vagrant plugin install vagrant-libvirt
```

**VirtualBox:**

```bash
sudo apt update
sudo apt install -y virtualbox vagrant   # or install VirtualBox/Vagrant per your OS (see Step 1 Alternative)
vagrant plugin install vagrant-vbguest
```

### Enter the lab directory

```bash
cd security-engineering-lab/labs/infrastructure/devops-linux-lab
```

### Start the lab

**KVM/libvirt** (from the lab root):

```bash
vagrant up
```

**VirtualBox** (from the same lab directory, no subdirectory needed):

```bash
vagrant up --provider=virtualbox
```

> Nested virtualization for the K3s/Kind/K3d workloads is enabled automatically for both providers in this Vagrantfile, but on VirtualBox it depends on your host CPU exposing VT-x/AMD-V to the guest — see [Known limitations](../../README.md#known-limitations) in the main README.

### Verify Lab 2

Check the VM status once startup is complete.

```bash
vagrant status
```

---

## Common Setup Notes

### Libvirt access issues

If Vagrant cannot connect to Libvirt, verify your user is in the `libvirt` group and that `libvirtd` is running.

```bash
groups
systemctl status libvirtd
```

### VirtualBox provider not found

If `vagrant up` reports it can't find the VirtualBox provider, confirm VirtualBox is installed and `VBoxManage` is on your `PATH`:

```bash
VBoxManage --version
```

On Linux, also make sure the `vboxdrv` kernel module is loaded (`sudo modprobe vboxdrv`); reinstalling the `virtualbox-dkms` package usually fixes a missing module after a kernel upgrade.

### Permission issues

If you are prompted for password access repeatedly, recheck group membership and restart your shell session.

### Box download issues

If box downloads fail, confirm your network connection and make sure Vagrant can reach the configured box source.

### Virtualization performance

If the host is underpowered, reduce the number of running VMs or allocate more memory and CPU.

---

## Verification Checklist

Before you continue using the labs, confirm the following:

- Vagrant is installed.
- Your chosen provider is installed and running:
  - **KVM/libvirt:** Libvirt is installed and running, KVM modules are loaded, and your user can manage libvirt domains.
  - **VirtualBox:** VirtualBox is installed, `VBoxManage --version` succeeds, and the `vboxdrv` kernel module is loaded (Linux only).
- Required Vagrant plugins are installed for your provider.
- The lab directory contains the expected `Vagrantfile` (root for KVM/libvirt, `virtualbox/` for VirtualBox).
- `vagrant up` starts the environment successfully.

---

## Uninstall and Cleanup

If you want to stop or destroy a lab environment:

```bash
vagrant halt
```

To destroy all VMs in the current lab:

```bash
vagrant destroy -f
```

**Easier option:** each lab ships an interactive Python manager that lists every machine's state and can start, halt, or destroy VMs individually or all at once, without you needing to remember Vagrant machine names. It's also `LAB_PROFILE`-aware, so it only shows the VMs that actually exist under your active profile:

```bash
cd labs/security/active-directory/base       # or active-directory/vlan-segmented / infrastructure/devops-linux-lab
python3 scripts/vagrant_manager.py
```

Use the manager's destroy option to remove every VM in the lab in one step (with a confirmation prompt).

You can also remove unused packages and clean up your system if needed.

---

## Troubleshooting

### Vagrant cannot find the provider

**KVM/libvirt:** make sure the `vagrant-libvirt` plugin is installed.

```bash
vagrant plugin list
```

**VirtualBox:** make sure VirtualBox itself is installed and `VBoxManage` is on your `PATH`; the VirtualBox provider ships with Vagrant, so no extra plugin is required.

```bash
VBoxManage --version
vagrant plugin list
```

### Libvirt service is not active

Start and enable the service.

```bash
sudo systemctl enable --now libvirtd
```

### VirtualBox kernel module not loaded (Linux)

Load the `vboxdrv` module, or reinstall `virtualbox-dkms` if it fails to load after a kernel upgrade.

```bash
sudo modprobe vboxdrv
sudo dpkg-reconfigure virtualbox-dkms   # Debian/Ubuntu, if the module still won't load
```

### KVM is missing

Confirm that your CPU supports virtualization and that it is enabled in BIOS/UEFI.

### VM startup fails

Check:
- Available RAM.
- Available disk space.
- Virtualization support.
- Network bridge or NAT configuration.

### Windows VM provisioning problems

For Lab 1, make sure the Windows-specific plugins are installed and that you started the Domain Controller first.

---

## Related Documentation

- [README](README.md)
- [Architecture Design](../architecture/architecture.md)
- [Security Scope](../security-scope.md)
- [Troubleshooting](troubleshooting.md)

---

## Notes

This project is intended for educational, defensive security, and authorized research purposes only.

All testing must be performed only in environments that you own or are explicitly authorized to use.

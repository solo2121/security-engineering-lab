# Platform support and prerequisites

Provider support, host requirements and Vagrant plugins. The short version is in the
[root README](../../README.md#provider-compatibility).

## Provider compatibility

Each full lab uses a provider-aware `Vagrantfile` supporting KVM/QEMU with libvirt and VirtualBox, subject to provider-specific requirements.

| Provider | Best for | Start command |
|---|---|---|
| **KVM/QEMU with libvirt** | Linux hosts with hardware virtualization and nested-virtualization support | `vagrant up --provider=libvirt` |
| **VirtualBox** | Compatible Intel/AMD x86_64 hosts running Linux, macOS, or Windows | `vagrant up --provider=virtualbox` |

KVM/QEMU with libvirt is the primary development provider for this project and is used for the main Linux validation workflows. It is the recommended provider for resource-intensive lab profiles on compatible Linux hosts.

> [!NOTE]
> **Supported** means the provider workflow is maintained and validated for the documented lab scope. It does not guarantee identical behavior across every host kernel, provider release, Vagrant plugin version, third-party Vagrant box revision, or hardware configuration.

### Current platform compatibility

| Lab | Linux x86_64 with libvirt | Intel/AMD x86_64 with VirtualBox | Apple Silicon / ARM64 |
|---|---|---|---|
| DevOps/DevSecOps Platform Lab | Supported | Supported | Not supported |
| Active Directory Security Lab | Supported | Supported | Not supported |
| Segmented Active Directory Lab | Supported | Supported | Not supported |
| Windows Server Hardening Lab (experimental) | Supported | Supported | Not supported |
| DevSecOps Lite — ARM64 | Not applicable | Not applicable | Planned |

The Segmented Active Directory Lab uses separate libvirt networks and isolated VirtualBox internal networks to model segmentation boundaries. VirtualBox networking provides logical isolation but does not reproduce physical IEEE 802.1Q VLAN tagging.

### Apple Silicon status

Apple Silicon uses the ARM64 architecture. Apple Silicon hosts are not currently supported or validated for the repository’s published lab workflows.

Although ARM64 Vagrant and virtualization workflows may be possible for selected Linux guests, the current lab portfolio depends on combinations of x86_64 Windows guests, x86_64 Vagrant boxes, guest media, provider-specific networking, nested-virtualization assumptions, and provisioning behavior that have not been validated on ARM64 hosts.

The following published labs are unavailable on Apple Silicon:

- Active Directory Security Lab
- Segmented Active Directory Lab
- Windows Server Hardening Lab
- The current full DevOps/DevSecOps Platform Lab
- Any workflow requiring x86_64-only Vagrant boxes, Windows guest media, or Intel/AMD-specific provider validation

A separate **DevSecOps Lite — ARM64** profile is planned for ARM64-native Linux and Kubernetes platform-engineering workflows. It is expected to focus on Kubernetes, GitOps, observability, runtime security, policy enforcement, and Linux administration.

Final component selection depends on end-to-end ARM64 validation across the selected provider or runtime, guest operating system, container images, Helm charts, networking, provisioning automation, and test coverage.

Until that profile is implemented and documented, Apple Silicon has no supported deployment path in this repository.

See the [Installation Guide](installation.md) for provider-specific setup instructions.

## Prerequisites

### Host requirements

- **Linux host:** Required for KVM/QEMU with libvirt full-lab workflows
- **Tested Linux distributions:** Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, and Debian 12 (see [SECURITY.md](../../SECURITY.md)). Fedora/RHEL-family install steps are documented in the Installation Guide but are not listed among the tested distributions
- **Linux, macOS, or Windows host:** Supported with VirtualBox on compatible Intel/AMD x86_64 hardware
- **CPU architecture:** Existing Windows Server and most current Vagrant box workflows require Intel/AMD x86_64 compatibility
- **Hardware virtualization:** Intel VT-x or AMD-V enabled in BIOS/UEFI where applicable
- **Vagrant:** A currently supported Vagrant release compatible with the selected provider
- **Virtualization provider:** KVM/QEMU with libvirt, or a supported VirtualBox release
- **Python:** Python 3.12+ for contributor tooling and lab-management utilities
- **Network:** Internet access for initial box, package, and container-image retrieval unless using prepared local or internal mirrors

### Recommended resources

Resource requirements vary by lab, selected provider, deployment profile, box-cache state, snapshot usage, and container-image storage.

Use the estimates in [Resource planning and profiles](../../README.md#resource-planning-and-profiles) as a baseline, then review the selected lab README before deployment.

For constrained systems, see [Minimal Resource Deployment](../guides/optimization/minimal-resource-deployment.md).

### Vagrant plugins

Install only the plugins required by your selected provider and lab.

Run the full prerequisite check first:

```bash
./scripts/check-prerequisites.sh --all
```

This validates host dependencies and enables lab-specific plugin checks. For the full list of provider- and lab-specific plugins for libvirt, VirtualBox, and Windows guest workflows, see the [Installation Guide](installation.md).

# Networking Architecture

## Overview

This lab uses a hybrid networking model that combines NAT, Linux bridges, and VLAN-style segmentation to simulate a realistic enterprise environment on a single host.

The design separates convenience networking (internet access and updates) from attack-surface networking (enterprise-style VLANs).

---

## Network Types Used

### 1. NAT Network

**Purpose:**

- Internet access for package updates and tooling.
- Not part of the attack simulation.

**Characteristics:**

- Provided by libvirt and Vagrant.
- DHCP-based.
- No inbound access from VLAN networks.
- Logically out of scope for exploitation.

> NAT exists strictly for usability, not realism.

---

### 2. VLAN Networks

**Purpose:**

- Simulate internal enterprise network segmentation.
- Enforce Layer 2 isolation between security zones.

**Implementation:**

- Linux bridges on the host.
- One bridge per VLAN.
- No routing, gateway, or firewall on the host by default.

**Security Properties:**

- Each VLAN is a separate broadcast domain.
- Hosts cannot communicate across VLANs without a Layer 3 device.
- This mirrors switch-level segmentation in enterprise environments.

---

## VLAN Layout

| VLAN ID | Name              | Subnet         | Purpose              |
|---------|-------------------|----------------|----------------------|
| 10      | Management / AD   | 172.28.10.0/24 | Domain infrastructure|
| 20      | Workstations      | 172.28.20.0/24 | User endpoints       |
| 30      | Servers & DevOps  | 172.28.30.0/24 | Internal services    |
| 40      | DMZ               | 172.28.40.0/24 | External-facing      |
| 99      | Attacker          | 172.28.99.0/24 | Red team platform    |

---

## OPNsense Firewall

**Status:** Direction documented, not yet implemented.

The Vagrant configuration documents OPNsense (`harmonnine/opnsense-kvm`) as the intended Layer 3 device for this lab, to provide inter-VLAN routing, firewall rules between segments, and realistic pivot/relay/bypass scenarios once built.

At this time:

- There is no OPNsense VM defined in the lab.
- No interfaces, DHCP, or firewall provisioning for OPNsense are in place.
- All inter-VLAN routing is effectively disabled.

This section will be updated with full configuration details once the OPNsense VM is added and provisioned.

---

## Attack Surface States

### Current state (no router)

- No inter-VLAN communication.
- Full Layer 2 isolation between VLANs.
- Only single-segment exploitation is possible.

### Future state (once OPNsense is implemented)

- Controlled inter-VLAN routing.
- Firewall rule and segmentation testing.
- Lateral movement and pivoting across VLANs.
- Segmentation bypass and misconfiguration scenarios.

---

## Design Decisions

- Linux bridges were chosen over NAT-only networking to model realistic east–west traffic and segmentation.
- No host-level routing is configured to avoid unrealistic shortcuts.
- Cross-segment attack paths must be earned through exploitation of future routing/firewall misconfigurations, not assumed connectivity.

This makes the lab suitable for professional red team and enterprise security training, not just CTF-style exercises.

---

## Related Files

- `scripts/setup-vlans.sh` — Creates VLAN bridges on the host.
- `scripts/attach-vms-to-vlans.sh` — Connects VMs to VLAN bridges.
- `scripts/test-vlans.sh` — Verifies segmentation and isolation.
- `diagrams/` — Network diagrams and topology visuals.

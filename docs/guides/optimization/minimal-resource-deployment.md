# Minimal-resource deployment

Both labs in this repo are enterprise-scale by design, and their default
configuration reflects that. This guide documents what's actually in each
`Vagrantfile` for running on smaller hosts — nothing here is aspirational,
every number below is pulled directly from the lab configuration.

Run [`scripts/check-prerequisites.sh`](../../../scripts/check-prerequisites.sh)
first to see where your host currently stands.

---

## Lab 2 (DevOps/DevSecOps lab) — has a built-in profile system

Lab 2's `Vagrantfile` already supports three resource profiles via the
`LAB_PROFILE` environment variable, so this is the easiest lab to right-size:

| Profile | VMs started | Approx. RAM |
|---|---|---|
| `minimal` (default) | `devops-1` (k3s control plane) + `worker-1` | ~10 GiB |
| `dev` | `minimal` + `node1` + `node2` (Ansible targets) | ~12 GiB |
| `full` | every defined VM (control plane, 2 workers, 4 OS labs, 2 Ansible nodes, kind lab, k3d lab, CI/CD server) | ~34 GiB |

```bash
cd labs/infrastructure/devops-linux-lab

# Smallest useful footprint — just the k3s control plane + one worker
LAB_PROFILE=minimal vagrant up

# Add Ansible target nodes
LAB_PROFILE=dev vagrant up

# Everything
LAB_PROFILE=full vagrant up
```

You can also start an arbitrary subset by name, bypassing the profile
entirely:

```bash
START_VMS=devops-1,worker-1,kind-lab vagrant up
```

Individual VM memory allocations (from the `Vagrantfile`), if you want to
build a custom subset:

| VM | Role | Memory |
|---|---|---|
| `devops-1` | k3s control plane | 8192 MB |
| `worker-1`, `worker-2` | k3s workers | 2048 MB each |
| `ubuntu-lab`, `rocky-lab`, `alma-lab`, `suse-lab` | OS hardening labs | 2048 MB each |
| `node1`, `node2` | Ansible targets | 1024 MB each |
| `kind-lab` | Kind cluster | 4096 MB |
| `k3d-lab` | k3d cluster | 4096 MB |
| `cicd-server` | Gitea + Jenkins + SonarQube + Vault + ZAP | 4096 MB |

## Lab 1 (Active Directory pentest lab) — selective VM startup

Lab 1's `Vagrantfile` has a `LAB_PROFILE` system (`minimal`, `ad`, `web`,
`cloud`, `llm`, `full`; default `ad`) — see the
[AD base lab README](../../../labs/security/active-directory/base/README.md#lab-profiles).
Its startup banner also documents a tested minimal set for 32 GiB hosts:

| VM | Role | Memory |
|---|---|---|
| `kali` | Attacker platform | 4096 MB |
| `dc01` | Domain Controller | 4096 MB |
| `win10` | Domain-joined workstation | 2048 MB |
| `ca01-esc` | AD CS (certificate services) | 4096 MB |
| `llm01` | Vulnerable LLM platform | 4096 MB |
| `cloud-pentest` | LocalStack cloud simulation | 2048 MB |

**Total for this subset: ~20 GiB.** The full lab (all 11 VMs — adds
`db01`, `linux01`, `print01`, `metasploitable2`, `juice-shop`) totals
**~29.5 GiB** and is recommended on hosts with 32 GiB+.

VMs outside the active profile are never defined, so `llm01` and
`cloud-pentest` require a profile that includes them (`full`). Start only
the subset you need by naming the VMs:

```bash
cd labs/security/active-directory/base
LAB_PROFILE=full vagrant up kali dc01 win10 ca01-esc llm01 cloud-pentest
```

If you're primarily practicing AD attack paths (Kerberoasting, ACL abuse,
ESC1/ESC8) rather than the full enterprise simulation, you likely don't
need `db01`, `print01`, or the legacy targets (`metasploitable2`,
`juice-shop`) at all — those exist for broader attack-surface practice,
not for the core AD kill chain.

## General tips for constrained hosts

- **Run one lab at a time.** The two labs use separate Vagrantfiles and
  separate private networks, but they still compete for the same host
  CPU/RAM/disk. Don't run both concurrently on a resource-constrained
  machine.
- **Swap is not a substitute for RAM here.** Both labs run multiple VMs
  doing real CPU work (AD replication, Kubernetes scheduling, certificate
  operations). Swapping under memory pressure will make provisioning
  time out rather than just run slowly.
- **Disk**: budget at least 40 GiB free for a minimal single-lab subset,
  100 GiB+ if you plan to run full profiles or keep both labs' VMs on
  disk simultaneously (even if not running at the same time).
- **Destroy what you're not using**: `vagrant destroy <name>` frees disk
  immediately; `vagrant suspend` frees CPU/RAM but keeps disk allocated.
- **Cloud alternative**: if your local host can't meet even the minimal
  profile, a cloud VM with nested virtualization enabled (e.g. a
  bare-metal or metal-adjacent instance type) can run either lab the same
  way — the requirement is KVM/libvirt support, not a physical machine
  specifically. Provider nested-virtualization support and pricing change
  frequently, so check current offerings rather than relying on
  specific recommendations here.

## Related documentation

- [`installation.md`](../../setup/installation.md) — full setup instructions
- [`scripts/check-prerequisites.sh`](../../../scripts/check-prerequisites.sh) — validates your host before you start
- [`troubleshooting.md`](../../setup/troubleshooting.md) — common setup issues

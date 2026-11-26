# Dependencies

This page is the single reference for what the repository needs to run,
develop against, and validate — host OS, Python, Kubernetes, external
security tools, and Python package dependencies. It complements the
step-by-step instructions in [`docs/setup/`](setup/) rather than
replacing them.

---

## Supported host operating systems

The labs are provisioned with Vagrant and support two providers: **KVM/libvirt**
(the default, Linux-only) and **VirtualBox** (cross-platform). See the
[README's Provider compatibility section](../README.md#provider-compatibility) for
an overview and [`docs/setup/installation.md`](setup/installation.md) for
full setup steps.

| OS family | KVM/libvirt | VirtualBox | Notes |
|---|---|---|---|
| Debian / Ubuntu (recent LTS) | Primary, most-tested target | Supported | Setup guides give `apt` commands for both providers. |
| Fedora / RHEL-family | Supported | Supported | Setup guides give `dnf`/`yum` equivalents where they differ. |
| macOS | Not supported | Supported | VirtualBox is Intel/AMD (x86_64) only — does not run on Apple Silicon/ARM. |
| Windows | Not supported | Supported | Use the native VirtualBox + Vagrant installers, or WSL2 with a Linux distribution above for KVM/libvirt. |

Nested virtualization (used by the DevOps/DevSecOps lab's K3s/Kind/K3d
workloads) is native on KVM/libvirt and must be explicitly enabled on
VirtualBox (`--nested-hw-virt on`, already set in this repo's VirtualBox
Vagrantfiles); actual nested-virt support still depends on your host CPU
exposing VT-x/AMD-V to the guest.

## Python

- **Required: Python 3.12+** for all first-party tooling under
  `tools/`, `tests/`, and `scripts/`. `tools/lib/` requires 3.12+ and
  uses modern union-type syntax (`X | Y`) and builtin generics
  (`list[int]`), so earlier interpreters are not supported.
- Individual lab automation scripts under `labs/security/*/scripts/`
  may pin their own dependency set — see each lab's `requirements.txt`.

## Kubernetes

- The `devops-linux-lab` (`labs/infrastructure/devops-linux-lab/`)
  runs a **K3s** cluster (currently pinned to `v1.31.4+k3s1` — see that
  lab's [`README.md`](../labs/infrastructure/devops-linux-lab/README.md)
  for the authoritative, up-to-date version table), with Harbor
  (container registry + Trivy scanning) and Argo CD (GitOps) deployed
  on top. A `k3d` (K3s-in-Docker) variant is also provided for a
  lighter-weight local setup.
- There are no standalone Kubernetes manifest files checked into this
  repository outside that lab's provisioning scripts.
- **Documentation drift (fixed in this pass):** `labs/infrastructure/devops-linux-lab/docs/k8s-setup.md`
  previously described an older `kubeadm` + Calico setup
  (`k8s-cp`/`k8s-w1`/`k8s-w2` hostnames) that no longer matched the
  current K3s-based architecture described in that lab's `README.md`.
  It has been rewritten to document the actual K3s setup and is now
  linked from [`docs/README.md`](README.md)'s index.

## Required external security tools

These are invoked by scripts under `tools/security/` and the lab
automation under `labs/security/`. Install via your OS package manager
unless noted otherwise.

| Tool | Used by | Notes |
|---|---|---|
| `nmap` | `tools/security/reconnaissance/nmap-menu.py` | |
| `amass` | `tools/security/reconnaissance/amass-scan.sh` | |
| `enum4linux` | `tools/security/reconnaissance/enum4linux-menu.py` | |
| `tcpdump` | `tools/security/network/tcpdump-wrapper.py` | requires elevated privileges to capture |
| `ettercap` | `tools/security/network/ettercap-menu.py` | lab/VLAN use only |
| `iptables`/`nft` (firewall tooling) | `tools/security/network/firewall-scan.sh` | |
| `vagrant` + `vagrant-libvirt` plugin (KVM/libvirt) or `vagrant-vbguest` plugin (VirtualBox) | all `labs/` environments | see [`docs/setup/`](setup/) |
| `qemu-kvm`/`libvirt` (KVM/libvirt) or Oracle VirtualBox (VirtualBox) | all `labs/` environments | pick one provider; see [`docs/setup/installation.md`](setup/installation.md) |
| `shellcheck` | CI, `make lint`, pre-commit | |
| `bats-core` | `tests/bash/`, `make test` | |

Run [`scripts/check-prerequisites.sh`](../scripts/check-prerequisites.sh)
to validate host-level prerequisites (KVM, libvirt, Vagrant, plugins,
resources) before standing up a lab with the KVM/libvirt provider — this
script does not currently check VirtualBox prerequisites — and
[`scripts/validate_lab.py`](../scripts/validate_lab.py) to validate the
repository itself (structure, docs, Vagrantfile syntax).

## Python package dependencies

### Runtime (used by individual tools/labs, install per-tool)

| File | Scope |
|---|---|
| [`labs/security/requirements.txt`](../labs/security/requirements.txt) | AD Pentest lab automation (`rich`, `pyyaml`, `aiofiles`, `requests`, `aiohttp`, `colorama`, `urllib3`) |
| `scapy` | `tools/security/network/scapy-port-scan.py` (install separately: `pip install scapy`) |
| `requests` | `tools/security/exploitation/exploit.py` and other HTTP-based tools |

`tools/lib/` (the shared utilities package) is standard-library only
by design — it adds no new runtime dependencies.

### Development

Pinned in [`requirements-dev.txt`](../requirements-dev.txt):

```
pylint
pytest>=9.1.1
pytest-cov
flake8
bandit
pre-commit
detect-secrets
ruff
black
mypy
```

`ruff`, `black`, and `mypy` are enforced in CI (`make format`, `make typecheck`
run the same checks locally) and are configured in
[`pyproject.toml`](../pyproject.toml). Run `black .` to fix formatting. They are
separate from the shellcheck-based `make lint` target.

Install with:

```bash
pip install -r requirements-dev.txt --break-system-packages
```

(`--break-system-packages` is only needed on distros with PEP 668
externally-managed environments; use a virtualenv instead if you
prefer.)

## Supply chain notes

- Development tooling is version-pinned with a lower bound
  (`pytest>=9.1.1`) rather than exact pins, to stay compatible with CI
  runner updates while still guaranteeing a minimum feature set.
- OS packages (`nmap`, `vagrant`, `shellcheck`, etc.) are intentionally
  **not** pinned to exact versions in documentation — they track
  whatever the host distribution provides, since this is a lab
  environment, not a production deployment target.
- `detect-secrets` runs in CI and pre-commit to catch accidental
  credential commits; see `.secrets.baseline` for the current
  allow-list.
- `bandit` findings in `tools/security/` are informational only —
  see [`SECURITY.md`](../SECURITY.md) for why offensive-security
  scripts intentionally trip some bandit rules.

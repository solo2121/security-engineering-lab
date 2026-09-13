# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **`KALI_BOX` / `KALI_BOX_VERSION` environment variables for
  `active-directory/base` and `active-directory/vlan-segmented`.** The
  attacker VM (still named `kali`) can now run an alternate
  Debian-based pentesting distribution instead of Kali Linux — for
  example Parrot Security — by overriding these two variables at
  `vagrant up` time. Defaults are unchanged (`kalilinux/rolling`,
  `2026.1.0`); no VM names, hostnames, IPs, or provisioning logic
  changed. This is an opt-in, unverified alternative — only the Kali
  default is covered by this repo's tests and Kali-specific guides.
  Both labs' `scripts/vagrant_manager.py` gained matching `--kali-box`
  / `--kali-box-version` CLI flags (set the same env vars for the
  subprocess) plus a new interactive menu option — `9` in
  `active-directory/base`, `[K]` in `active-directory/vlan-segmented`
  — that prompts to switch between Kali, Parrot, or a custom box, and
  both now display the active attacker box in their banner and menu
  title when overridden.
- **Provider-aware `vagrant_manager.py` for `active-directory/base` and
  `active-directory/vlan-segmented`.** Both managers gained a
  `resolve_provider()` helper (CLI `--provider` flag → `VAGRANT_DEFAULT_PROVIDER`
  → OS-based default), matching the pattern already used by
  `devops-linux-lab`'s manager and the Vagrantfiles' own
  `current_provider()` logic. `--provider` is now passed explicitly to
  `vagrant up`/`reload`, and the resolved provider is shown in the
  startup banner and interactive menu title. The VLAN lab's manager
  previously hardcoded `VAGRANT_DEFAULT_PROVIDER=libvirt` in
  `build_vagrant_environment()`, silently ignoring any VirtualBox
  selection made at the Vagrantfile level; this is fixed.

### Changed
- **Unified `Vagrantfile` architecture for `active-directory/base` and
  `active-directory/vlan-segmented`.** Both labs previously shipped two
  provider-specific Vagrantfiles (`Vagrantfile` for libvirt,
  `virtualbox/Vagrantfile` for VirtualBox) with duplicated VM
  definitions and provisioning logic. Each lab now has a single
  `Vagrantfile` with `config.vm.provider` blocks for both libvirt and
  VirtualBox, selected via `--provider` or `VAGRANT_DEFAULT_PROVIDER`
  (same convention as `devops-linux-lab`, which was already unified).
  No VM names, IPs, profiles, or provisioning logic changed for
  `active-directory/base`.
  For `active-directory/vlan-segmented`, the two source Vagrantfiles had
  functionally diverged before this merge — the VirtualBox variant had
  accumulated a fuller LLM01 OWASP Top-10 module, a Terraform
  state-file secrets-exposure scenario for `cloud-pentest`, and an
  LDIF-based AD CS template-creation technique that the libvirt variant
  never received. The unified Vagrantfile runs that fuller content
  under both providers; the libvirt-only VM_CONFIG box_version pinning
  (silently missing from the old VirtualBox file) was also restored for
  both providers, and OPNsense's box name is now provider-conditional
  (`harmonnine/opnsense-kvm` vs. `harmonnine/opnsense` — different
  builds per hypervisor).
  Both obsolete `virtualbox/Vagrantfile`s were removed, along with every
  reference to them in `Makefile`, `.github/workflows/ci.yml`,
  `tests/python/test_validate_lab.py`, `.secrets.baseline`
  (regenerated), and README/docs repository-wide.
- Root `README.md` gained a table of contents, a dedicated
  **Prerequisites** section, a **Quick start** section (clone → validate
  host → `vagrant up`), a **Common workflows** section (rebuild,
  snapshot, `vagrant_manager.py` usage, attack-simulation pointers), and
  a **Troubleshooting** section — previously this content only existed
  scattered across `docs/setup/*.md` with no root-level summary or
  entry point. Also fixed two lines left over from before the
  Vagrantfile unification above that still described "a VirtualBox-compatible
  `Vagrantfile`" as a separate per-provider file.
- Fixed four broken relative links found in a repository-wide audit:
  two `../../../LICENSE` links in `active-directory/base/README.md` and
  `active-directory/vlan-segmented/README.md` were one directory level
  too shallow (both files are four levels below the repo root, not
  three); a `../../infrastructure/devops-linux-lab/` link in the
  VLAN lab's README was similarly one level too shallow; and
  `vlan-segmented/docs/requirements.md`'s link to
  `docs/setup/troubleshooting.md` was one level too shallow.

### Changed
- **Documentation sync for the `active-directory/` rename and `LAB_PROFILE`
  rollout.** `labs/security/ad-pentest/` and `labs/security/ad-pentest-vlan/`
  were renamed to `labs/security/active-directory/base/` and
  `labs/security/active-directory/vlan-segmented/` in a prior commit, and the
  base lab's `Vagrantfile`/`scripts/vagrant_manager.py` gained `LAB_PROFILE`
  support (default `ad` profile: 6 VMs; `LAB_PROFILE=full`: all 11) with an
  assisted profile-switch prompt for VMs outside the active profile. Neither
  change had been propagated through the rest of the repository's
  documentation. Updated every stale `ad-pentest`/`ad-pentest-vlan` path
  reference to `active-directory/base`/`active-directory/vlan-segmented`
  across `README.md`, `SECURITY.md`, `CONTRIBUTING.md`,
  `.github/ISSUE_TEMPLATE/*.md`, `docs/**/*.md`,
  `labs/security/README.md`, `labs/security/requirements.txt`,
  `labs/infrastructure/devops-linux-lab/README.md`,
  `tools/security/README.md`, and the base/vlan-segmented labs' own
  remaining internal references. Also fixed a broken `cd
  labs/security/ad-pentest` in `labs/security/active-directory/base/README.md`'s
  Attack Automation section (missed by the prior Quick Start fix) and
  updated its stale "Version 1.12 Highlights" heading to v1.13.
- `docs/setup/installation.md` — the "easier option" manager-script snippet
  told readers to run `./scripts/vagrant-manager.sh` for any of the three
  labs, but that script was removed from the base Active Directory lab
  (`scripts/vagrant_manager.py` is now its only supported manager) and is
  discouraged in favor of `vagrant_manager.py` for the VLAN lab as well.
  Updated the snippet and surrounding text accordingly.
- `labs/security/README.md` — the "Available Labs" table and every
  Quick Start / Common Workflows command still referenced the pre-rename
  `ad-pentest`/`ad-pentest-vlan` paths and the removed
  `./scripts/vagrant-manager.sh`. Updated paths, switched commands to
  `python3 scripts/vagrant_manager.py`, refreshed the base lab's version
  (`v1.12` → `v1.13`), and noted that both labs are now `LAB_PROFILE`-scoped
  rather than always creating every listed host.
- Root `README.md`'s repository-structure tree listed `scripts/bootstrap/`,
  `scripts/utilities/`, `examples/configs/`, and `examples/templates/`,
  none of which exist on disk, and didn't show the `active-directory/base/`
  and `active-directory/vlan-segmented/` split under
  `labs/security/active-directory/`. Corrected the tree to match the actual
  layout.
- `examples/README.md` described `configs/` and `templates/`
  subdirectories that don't exist yet. Reworded to describe the directory's
  actual (currently empty) state instead of implying that content is
  already there.

### Added
- `docs/architecture/emergency-isolation-runbook.md` — home-lab runbook for
  the scenario where a lab VM, network, or bridge is suspected of reaching
  the real internet or a trusted network unexpectedly: containment,
  evidence preservation, credential rotation, destroy-vs-restore guidance,
  and a reconnection checklist. Linked from `docs/README.md` and
  cross-referenced from `docs/security-scope.md`'s Lab Isolation
  Requirements section. Not a substitute for an enterprise incident-response
  plan.
- `SECURITY.md` — `## Repository-Level Controls (GitHub Settings)` section,
  distinguishing controls verifiable from this repository's own content
  (Dependabot config, SHA-pinned Actions, `detect-secrets` baseline) from
  controls that live in GitHub repository settings and can't be confirmed
  by reading the repository (branch protection/rulesets, secret scanning
  and push protection, Dependabot alerts, code scanning, Actions
  permissions). Doesn't claim any of the settings-based controls are
  currently enabled — only names them as items to verify directly in
  GitHub.

### Changed
- `docs/setup/installation.md` — the "Recommended host resources" section
  now gives concrete minimum/recommended RAM and disk figures per lab
  (sourced from `minimal-resource-deployment.md` and
  `labs/security/ad-pentest-vlan/README.md`'s profile table) instead of
  only qualitative descriptions ("high", "moderate to high") behind a
  link. The full VM-by-VM breakdown still lives in
  `minimal-resource-deployment.md`, linked at the end of the section.
- `docs/guides/infrastructure/kubernetes-security-hardening.md`,
  `docs/guides/infrastructure/complete-devops-platform-guide.md`, and
  `docs/guides/security/llm-security-compliance-lab.md` — the kubescape,
  k3d, and Ollama install commands were previously a bare `curl | bash` /
  `curl | sh` with an inspect-first comment above them (see the prior
  `Fixed` entry below). Replaced with an actual download → inspect (`less`)
  → execute → clean-up sequence, so the inspection step is something the
  reader does, not just something the doc suggests. URLs, curl flags, and
  the original shell interpreter (`bash` or `sh`) are unchanged in all
  three. `docs/guides/security/ad-mitre-log-source-playbook.md`'s LinPEAS
  line was intentionally left as a one-liner — see the `CONTRIBUTING.md`-
  adjacent rationale in the audit response for why (it's a technique
  reference/cheat-sheet entry alongside other one-line fetch-and-run
  examples like the PowerUp `IEX` download-cradle immediately below it,
  not a one-time setup step; expanding only that one line would break the
  format without a corresponding safety benefit for an already-compromised
  lab target).
- `tools/sysadmin/utilities/git-management.sh` — consolidated four separate
  `set -o errexit` / `set -o errtrace` / `set -o nounset` / `set -o
  pipefail` lines into `set -Eeuo pipefail`, matching the single-line style
  already used by 11 other scripts in `tools/` and `labs/*/scripts/`. Same
  options, same behavior (including `errtrace`, which this script's `trap
  ... ERR` handler depends on) — purely a style consolidation.
- `.github/workflows/ci.yml` — pinned `actions/checkout` and `actions/setup-python` from the mutable `@v7` tag to the exact commit SHA that tag currently resolves to (`actions/checkout@3d3c42e...` = v7.0.1, `actions/setup-python@5fda3b9...` = v7.0.0), with a version comment on each line. Tags are mutable and can be force-moved; a pinned SHA can't change without a new commit. `dependabot.yml` already watches the `github-actions` ecosystem, so it will open PRs to bump the pin on new releases.
- `.github/workflows/ci.yml` / `Makefile` — the Python coverage step was informational only (`|| true`, couldn't fail the build). Changed to `--cov-fail-under=80`, an enforced minimum. Current coverage is 85%, so this has headroom for normal work while still catching a real regression.
- `tools/security/reconnaissance/amass-scan.sh` — added `set -Eeuo pipefail` to match the strict-mode convention used by every other script in `tools/`. This required initializing `DOMAIN=""` and `OUTPUT_DIR=""` up front, since both were previously read (`[ -z "$DOMAIN" ]`) before ever being assigned a default — harmless without `-u`, but would have aborted with "unbound variable" the moment strict mode was turned on.
- `tools/security/reconnaissance/amass-scan.sh` — fixed a pre-existing bug where every error path (`Domain argument is required`, `Unknown option`, `Too many arguments`) exited with status `0` instead of `1`. All three called `show_help()`, which unconditionally did `exit 0` internally, so the `exit 1` written right after each call was dead code. Moved the `exit 0` out of `show_help()` and into the one call site that legitimately wants it (`-h`/`--help`). Verified `--help` (0), no-args (1), `-s` with no value (1), too many args (1), and an unknown flag (1) all now return the correct exit code.

### Fixed
- `docs/README.md` — `guides/security/domain-compromise-walkthrough.md` was
  a real, linked-to file (from `docs/project/learning-path.md`) but was
  missing from the Security guides table in the docs index. Added.
- Root `README.md` — the repository structure tree showed `workflows/` as a
  direct child of `docs/`, but it actually lives at
  `docs/guides/workflows/`; the tree also omitted `docs/project/` and
  `docs/setup/`, and omitted `tools/lib/` under `tools/`. Corrected the
  tree to match the actual layout, and added a `Documentation Index` entry
  to the Documentation hub table linking to `docs/README.md`. Also added
  `make docs-refs` to the Development quickstart snippet and a pointer to
  `make help` for the remaining targets (`make format`, `make typecheck`,
  `make coverage`, `make validate-repo`, `make docs`, `make prereq`), none
  of which were previously mentioned outside the Makefile itself.
- `CONTRIBUTING.md` referenced `pylint` as the required Python linter in three places (Local Setup command, Code Standards, PR Checklist), but CI, the `Makefile`, and `.pre-commit-config.yaml` all actually enforce `flake8`. Updated the doc to match what's enforced.
- `requirements-dev.txt` was almost entirely unpinned and missing a trailing newline. Added `>=` version floors for every entry (`flake8`/`detect-secrets` pinned to match the exact versions already used in `.pre-commit-config.yaml`; the rest floored at current stable releases), and added the missing trailing newline.
- Added a one-line reminder to inspect the script before piping to a shell above each `curl | bash` / `curl | sh` install command in `docs/guides/infrastructure/kubernetes-security-hardening.md`, `docs/guides/infrastructure/complete-devops-platform-guide.md`, `docs/guides/security/ad-mitre-log-source-playbook.md`, and `docs/guides/security/llm-security-compliance-lab.md`. Commands themselves are unchanged.

### Added
- `scripts/check_doc_references.py` (+ `tests/python/test_check_doc_references.py`) — scans doc-index bullets/tables (e.g. `` - **`docs/foo.md`** – ... ``) for backtick-quoted filenames that don't resolve to a real file on disk. `markdown-link-check` only validates real `[text](path)` Markdown links, so a plain-text filename reference like the stale `docs/network-map.md` in `labs/security/README.md` could go unnoticed indefinitely; this closes that gap. Wired into `make docs-refs`, a new blocking step in the `check-doc-links` CI job (it's local and deterministic, unlike the informational `markdown-link-check` step), and a new local pre-commit hook.
- `## Provisioning Philosophy` section in `docs/architecture/architecture.md` — states explicitly why each lab uses a single Vagrantfile with inline shell provisioners instead of Ansible roles (single-host lab, fewer dependencies to install, provisioning logic co-located with what it provisions), and links to the roadmap item that would revisit this if the labs grow enough to justify it.
- `scripts/README.md` — index for `check-prerequisites.sh` and `validate_lab.py`, matching the README convention already used by `assets/`, `docs/`, `labs/`, `tests/`, and `tools/`. Linked from the root `README.md` documentation hub table.
- `## Lab Documentation` section in each lab's `README.md` (`labs/infrastructure/devops-linux-lab/`, `labs/security/ad-pentest/`, `labs/security/ad-pentest-vlan/`), linking to every file under that lab's own `docs/`. Previously `devops-linux-lab/docs/*.md` (6 files) and `ad-pentest/docs/attack-guide.md` + `docs/lab-credentials.md` were not linked from their lab README at all, and `ad-pentest-vlan/docs/*.md` only appeared inside an ASCII directory tree rather than as clickable links.
- `quickstart-examples.md` entry in `docs/setup/README.md` — the file was already linked from `docs/README.md` and `docs/architecture/architecture.md`, but missing from its own section's index.
- **CI:** Added caching for apt packages and Vagrant plugins to the `validate-vagrantfiles` job, significantly reducing its runtime.
- `tests/python/` — pytest unit tests for Python tooling logic (argument parsing, data structures).
- `tests/bash/` — bats unit tests for Bash script helper functions and configuration tables.
- `run-tests` CI job running pytest and bats on every push/PR.
- `check-doc-links` CI job that scans all markdown files for broken links and reports findings; informational only, does not fail the build (external link rot and rate limits are expected).
- `.pre-commit-config.yaml` — shellcheck, flake8, detect-secrets, and markdown-link-check hooks for local commit-time validation. Unlike the CI job, the local `markdown-link-check` hook blocks the commit so broken internal links are caught before they're pushed.
- `.secrets.baseline` — audited baseline of intentional lab credentials (AD pentest creds, Vagrantfile test passwords, LocalStack fake AWS key) so `detect-secrets` only flags genuinely new findings.

### Changed
- `assets/README.md` now documents the expected purpose of each asset category (diagrams, screenshots, icons, banners, logos) so contributors know where new asset types belong before adding a subfolder.

### Fixed
- `pyproject.toml` — `ruff`, `black`, and `mypy` were configured against `target-version = "py311"` / `python_version = "3.11"`, while `docs/dependencies.md` documents "Required: Python 3.12+" and CI installs Python 3.12 in every job. Bumped all three tool configs to target 3.12 to match what's actually required and installed, rather than leaving the linting/type-checking config silently out of sync with the documented minimum version.
- `.secrets.baseline` was stale: it still listed findings under old filenames (`docs/guides/infrastructure/Complete-DevOps-Platform-Guide.md`, `labs/security/ad-pentest/docs/ATTACK_GUIDE.md`, `labs/security/ad-pentest/docs/LAB_CREDENTIALS.md`, `labs/security/ad-pentest-vlan/docs/ATTACK_GUIDE.md`) from before those files were renamed to kebab-case, and had no entries for the current filenames or for `docs/guides/security/domain-compromise-walkthrough.md` / `labs/infrastructure/devops-linux-lab/Vagrantfile`. This meant `detect-secrets` (in both the pre-commit hook and the CI `security` job) would treat the already-known, already-reviewed lab credentials in those files as brand-new findings the next time anyone touched them. Regenerated the baseline with `detect-secrets scan --baseline .secrets.baseline`.
- Removed a stale `docs/archive/` exclude filter from `.secrets.baseline` and `.pre-commit-config.yaml` (`detect-secrets` hook); `docs/archive/` was deleted in a prior commit and the filter matched nothing.
- `SECURITY.md` referenced the old filename `LAB_CREDENTIALS.md`; updated to link the current `labs/security/ad-pentest/docs/lab-credentials.md`.
- Removed the "Reference archive" section from `docs/README.md` and the `docs/archive/` entry from the repository structure tree in the root `README.md`; both pointed at `docs/archive/`, which was deleted in a prior commit but never unlinked from the index.
- Fixed an undefined `counter` variable in `tools/sysadmin/utilities/timeshift-manager.sh` (`delete_snapshot`/`restore_snapshot`) that caused the script to abort under `set -u` when selecting a snapshot to delete or restore; now derived from `${#snapshot_array[@]}`.
- Broken relative links in `docs/architecture/architecture.md`, `docs/workflows/WORKFLOWS.md`, `docs/guides/infrastructure/proxmox-host-setup.md`, and `labs/security/ad-pentest/README.md` left over from the docs reorganization.
- Removed unresolved git merge-conflict markers (`<<<<<<<`/`=======`/`>>>>>>>`) that had been committed into `labs/security/ad-pentest/docs/attack-guide.md` and `docs/guides/security/domain-compromise-walkthrough.md`, along with the stale `exch01`/`sp01`/`pnpt-internal` content on the losing side of each conflict.
- Removed leftover editorial placeholder text from `labs/security/ad-pentest-vlan/docs/attack-guide.md`.
- Synced `labs/infrastructure/devops-linux-lab/README.md`, `docs/lab-guide.md`, `labs/security/ad-pentest/README.md` (+ `docs/attack-guide.md`, `docs/lab-credentials.md`), `labs/security/ad-pentest-vlan/README.md` (+ `docs/attack-guide.md`), `labs/security/README.md`, and the top-level `README.md` with the current state of all three Vagrantfiles.

### Planned
- Additional AD CS attack scenarios.
- Ansible role automation for the DevOps lab.

---

## [8.2.0] - 2026-07-31 — DevOps / DevSecOps Lab

### Added
- Integrated CI/CD server (`cicd-server`) running Gitea, Jenkins, SonarQube, HashiCorp Vault, and OWASP ZAP for a complete DevSecOps pipeline.
- Gitleaks and Trivy CLI tools on `cicd-server` for automated secret and container image scanning.
- Sample Jenkins pipeline (`DevSecOps-Pipeline.groovy`) and sample Flask app, wired to Gitea checkout, Gitleaks, Trivy, and a Harbor push.
- Port forwarding for Gitea (3000), Jenkins (8080), Jenkins agent (50000), SonarQube (9000), Vault (8200), and ZAP (8090).

### Known Issues
- `devops-1`'s Ingress NGINX forward (guest `80`) and Jenkins on `cicd-server` both default to host port `8080`. Running both VMs together (e.g. `LAB_PROFILE=full`) fails with a Vagrant port-collision error. Workaround: don't start both at once, or change `JENKINS_PORT` in the Vagrantfile before `vagrant up`.

---

## [1.12] - 2026-07-31 — AD Pentest Lab

### Fixed
- Moved plugin validation inside the `Vagrant.configure` block to prevent false-positive failures.
- Added error handling for a missing or unloadable `config.rb`.
- Fixed `vagrant-hostmanager` alias syntax (aliases are now a proper array of strings).
- `configure_windows_comm` now accepts `boot_timeout` and `winrm_timeout` parameters; DC01 keeps extended 7200s timeouts for AD promotion while other Windows VMs use the 3600s default.
- Added CPU/memory validation with warnings for out-of-range values.
- Fixed duplicate `/etc/hosts` entries on `kali` and `linux01`.
- Added SSH key management for `linux01`, `metasploitable2`, and `juice-shop`.
- Juice Shop's Docker container now runs with `--restart=always` and pulls the image explicitly before first run.
- Polkit CVE-2021-3560 provisioning on `linux01` no longer aborts if the service restart fails.

---

## [2.1.5] - 2026-07-31 — AD Pentest VLAN Lab

### Fixed
- Added named WinRM timeout constants; `DC01` keeps extended timeouts (10800s boot, 7200s communication) for AD promotion, while other Windows VMs use 7200s / 3600s defaults.
- `configure_windows_comm` now accepts optional `boot_timeout` / `winrm_timeout` parameters instead of hardcoding DC01-specific values inline.
- Plugin installation now fails loudly if `vagrant plugin install` does not succeed, instead of continuing silently.
- Resolved an undefined variable (`ca01_ip` → `vm_ip`) in the `CA01-ESC` DNS record that could cause DNS registration to silently no-op.

---

## [2.2.0] - 2026-07-14 — AD Pentest VLAN Lab

### Changed
- Vagrantfile header now documents OPNsense (`harmonnine/opnsense-kvm`) as
  the intended firewall/router for VLAN segmentation, replacing the
  earlier planned-but-never-implemented pfSense reference. VM definition,
  interface mapping, DHCP, and firewall provisioning are not yet
  implemented — lab topology and VM count (14) are unchanged from v2.1.3.

---

## [2.1.3] - 2026-07-08 — AD Pentest VLAN Lab

### Fixed
- Static IP configuration now uses 5-method adapter detection (target IP,
  lab subnet match, adapter name, non-NAT exclusion, and a debug fallback),
  plus disabled Duplicate Address Detection and set `SkipAsSource=false`.
- Windows Defender disabled via a registry-only approach (silent, reliable).
- AD promotion (`Install-ADDSForest`) now uses explicit named parameters.
- Domain DN and DNS A records hardcoded as literals to avoid Ruby
  interpolation edge cases.
- Silenced a harmless `Set-NetConnectionProfile` error on domain-joined VMs.
- Pinned exact box versions for `metasploitable2` and `juice-shop`.

---

## [1.10.0] - 2026-07-07 — AD Pentest Lab (Enterprise Edition)

### Changed
- Centralized all VM constants (IPs, memory, etc.) in the Vagrantfile.
- Created a reusable domain-join function, removing 300+ lines of duplication.
- Added vagrant-hostmanager integration.
- Pinned all Ubuntu box versions.
- Added health checks and debug mode.
- Reduced LLM01 RAM to 4GB (was 8GB).
- Added external config support (`config.rb`).
- Improved error handling in all PowerShell scripts.
- Added provisioning checkpoints.

### Fixed
- Static IP configuration now uses 5-method adapter detection.
- Windows Defender disabled via registry-only approach.
- AD promotion now uses explicit parameters.
- Domain DN hardcoded for correct PowerShell interpolation.
- DNS records hardcoded with IP addresses.
- Silenced a harmless `Set-NetConnectionProfile` error.

---

## [1.9.0] - 2026-07-03 — AD Pentest Lab (Enterprise Edition)

### Added
- Modern Active Directory attack vectors and expanded AD CS attack paths (ESC1–ESC9).
- Enhanced Linux, Windows, Cloud, and LLM/AI attack scenarios.

### Fixed
- CA01 vs `ca01-esc` inconsistency across the lab: only `ca01-esc` (172.28.128.25, CA name `LAB-ESC-CA`) is actually provisioned; docs, configs, and attack commands previously referenced a nonexistent `CA01` host at `.24`.
- Removed stale `/etc/hosts` entries in the Vagrantfile pointing to the phantom `CA01` host.
- Corrected resource budget calculation that double-counted a nonexistent VM (VM count 15 → 14, ~47.5GB → ~43.5GB).
- Removed unsupported `after` blocks in the Vagrantfile to restore `vagrant validate` functionality.
- Fixed the machine inventory table and network diagram in the lab README, the wrong IP in the attack guide's network map, and the ESC1/ESC8 example commands in the AD MITRE log-source playbook that referenced the wrong CA name and hostname.
- Applied additional stability, security, and provisioning fixes; improved documentation and overall lab reliability.

---

## [8.1.0] - 2026-07-03 — DevOps / DevSecOps Lab

### Added
- Automated DevSecOps attack scenarios and intentionally vulnerable deployments.
- Backdoored image build and Harbor push scenario.
- Terraform state file with intentionally leaked secrets for Infrastructure as Code (IaC) security practice.
- Indirect prompt injection (RAG) scenario for AI/LLM security testing.

---

## [2.1.2] - 2026-06-20 — AD Pentest VLAN Lab

### Fixed
- Dynamic Linux interface detection, removing hardcoded `eth1`.
- Production-grade Windows static IP configuration, preventing provisioning hangs.
- Domain join hostname rename checks to prevent duplicate joins.
- Improved DC readiness detection with a ping check before domain join.
- Windows Defender disabled via a dedicated function.
- Domain name defined as a literal in PowerShell blocks to prevent Ruby interpolation issues.
- Correct RAM calculation banner now accounts for all VMs.
- Vagrant plugin check for `vagrant-reload` now shows a clear error message.
- Libvirt default prefix cleared to prevent VM name collisions.

---

## [8.0.0] - 2026-06-19 — DevOps / DevSecOps Lab

### Added
- OpenTofu v1.8.0 installed alongside Terraform.
- Kind lab VM with a fully automated multi-node Kubernetes-in-Docker cluster: 1 control plane and 2 workers.
- K3d lab VM with a fully automated K3s-in-Docker cluster: 1 server and 2 agents.
- Interactive Harbor password prompt using `io/console`, removing hardcoded credentials.
- Environment-based password handling using `HARBOR_PASS`.
- Dynamic architecture detection for binary downloads (`amd64` / `arm64`).
- `scripts/vagrant-manager.sh` for interactive management of all VMs by group.
- `scripts/validate-lab.sh` for automated health checks across all lab services.
- Pre-configured `kubectl` aliases on Kind and K3d VMs.

### Fixed
- Argo CD CRD deletion now uses `--wait=false` to prevent finalizer hangs.
- Kyverno now uses 3 retries with full namespace cleanup between attempts.
- Docker daemon is reconfigured after Harbor install to trust the registry before seeding.
- Worker provisioner no longer uses the invalid `--flannel-backend` flag.
- Terraform download now uses dynamic architecture detection instead of hardcoded `amd64`.

---

## [2.1.1] - 2026-06-18 — AD Pentest VLAN Lab

### Added
- ZeroLogon (`CVE-2020-1472`) attack path.
- PetitPotam (`CVE-2021-36942`) NTLM relay coercion.
- NoPac (`CVE-2021-42287`) SAM account name spoofing.
- Resource-Based Constrained Delegation (`RBCD`) misconfiguration.
- Enhanced PrintNightmare (`CVE-2021-1675` / `CVE-2021-34527`).
- AD CS ESC9 — No Security Extension.
- Shadow Credentials attack path.
- Auto-generated attack cheat sheet on the Kali VM at `/root/attacks/README.txt`.

---

## [1.8.0] - 2026-06-17 — AD Pentest Lab (Flat Network)

### Added
- NoPac (`CVE-2021-42287`) SAM account name spoofing attack path.
- Resource-Based Constrained Delegation (`RBCD`) misconfiguration.
- AD CS ESC9 — No Security Extension certificate template.
- LLMNR/NBNS poisoning enabled by default for Responder practice.
- Additional Kerberoastable service accounts.
- Automated plugin check and install for `vagrant-reload` and `vagrant-libvirt`.

---

## [2.1.0] - 2026-06-16 — AD Pentest VLAN Lab

### Added
- Enterprise VLAN segmentation across 5 subnets: Management, Workstations, Servers, DMZ, and Attacker.
- 14-VM enterprise topology with Windows Server 2022 DC, CA, Exchange, SharePoint, SQL Server, and Print Server.
- LocalStack AWS attack simulation with S3, IAM, and EC2.
- 15 LLM security research endpoints for prompt injection, RAG poisoning, and token abuse.
- OWASP Juice Shop and Metasploitable2 legacy targets.
- VLAN setup and validation scripts: `setup-vlans.sh`, `test-vlans.sh`.
- Network architecture diagram in Mermaid.
- Vagrant plugin check with automatic install on first run.

### Fixed
- DC readiness detection before domain join.
- Worker node join sequencing.
- Shell variable expansion in Python heredoc blocks.

---

## [7.1.1] - 2026-06-16 — DevOps / DevSecOps Lab

### Fixed
- Python heredoc quoting updated to prevent shell variable expansion (`<<'PYEOF'`).
- Variables are now passed as environment variables into Python generation blocks.
- `registries.yaml` generation syntax errors corrected.

---

## [1.7.0] - 2026-06-15 — AD Pentest Lab (Flat Network)

### Added
- Windows Server 2022 Domain Controller with full AD CS attack paths from ESC1 to ESC9.
- Kali Linux attacker VM with automated tooling.
- Dynamic domain DN construction from `DOMAIN_NAME`.
- Memory warning banner at `vagrant up` time.
- Plugin auto-install for `vagrant-reload` and `vagrant-libvirt`.
- Service accounts, delegation paths, and intentional ACL misconfigurations.
- `LAB_CREDENTIALS.md` with full account inventory.
- `ATTACK_CHAIN.md` documenting ESC8 → NTLM relay → domain compromise path.

### Fixed
- Improved DC provisioning reliability with retry logic.
- Domain join sequencing with proper readiness checks.

---

## [7.1.0] - 2026-06-15 — DevOps / DevSecOps Lab

### Changed
- Python is now used to generate `registries.yaml` for Harbor registry configuration.

---

## [1.0.0] - 2026-06-13 — Initial Public Release

### Added
- Repository structure with `labs/`, `security/`, `sysadmin/`, and `docs/`.
- Security tooling for audit, exploitation, network, reconnaissance, and wireless.
- Sysadmin scripts for automation, monitoring, system hardening, and utilities.
- Documentation for architecture, guides, workflows, and archive.
- `requirements-dev.txt` for contributor Python dependencies.
- MIT License, Code of Conduct, Security Policy, and Contributing guidelines.

---

## [7.0.0] - 2026-05-29 — DevOps / DevSecOps Lab

### Added
- k3s Kubernetes cluster with 1 control plane and 2 workers.
- Harbor container registry with airgap image seeding of 40+ images.
- Argo CD GitOps platform v7.7.5.
- Prometheus, Grafana, and Loki observability stack.
- Falco runtime security.
- Kyverno policy enforcement.
- Cert-Manager TLS automation.
- Terraform v1.9.8 with bash completion.
- Multi-profile deployment: `minimal`, `dev`, `full`.
- Zero-cache Harbor mode (`CACHE_MODE=zero`).
- Dynamic libvirt network auto-detection.
- Linux practice nodes: Ubuntu 24.04, Rocky Linux 10, AlmaLinux 10, openSUSE Leap 15.6.
- Ansible management nodes.
- Day-2 tools: k9s, kubectx, kubens, stern.
- Idempotency markers for all provisioners to support safe re-runs.
- Per-tool installation markers for granular retry.

---

## Versioning Policy

- **MAJOR** — Incompatible changes to lab architecture or workflow.
- **MINOR** — New VMs, tools, or features added.
- **PATCH** — Bug fixes and provisioning reliability improvements.

---

## Reporting Changes

To report a bug, request a feature, or suggest improvements:

1. Check [GitHub Issues](https://github.com/solo2121/security-engineering-lab/issues).
2. If it is not already reported, create a new issue with reproduction steps and environment details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing changes.

---

## License

[MIT License](https://github.com/solo2121/security-engineering-lab/blob/main/LICENSE)

Copyright (c) 2023–2026 Miguel A. Carlo

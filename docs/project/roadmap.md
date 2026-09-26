# Roadmap

This roadmap is a working list of ideas for future improvements. It is not a commitment to dates or deadlines—priorities may change based on what is most useful next. These labs are maintained independently and shared to help others get hands-on practice. Contributions and suggestions are welcome; see [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

For a log of what has already been released, see [`CHANGELOG.md`](../../CHANGELOG.md).

## Near-term

- [ ] Add a recorded demo (asciinema or GIF) to the README showing `vagrant up` provisioning and an Active Directory attack chain in action.
- [x] Expand automated test coverage across additional `sysadmin/` and `security/` scripts — added `user-audit.sh` (`tools/sysadmin/system-hardening/user-audit.sh`, covered by `tests/bash/test_user_audit.bats`), joining `log-analyzer.sh`, `setup-vlans.sh`, and `port-scanner.py`. Many other `sysadmin/` and `security/` scripts still have no tests — contributions toward closing that gap are welcome.

## Mid-term

- [ ] Add AD CS attack scenarios beyond the current ESC1/3/4/6/7/8/9 coverage — ESC2, ESC11, and ESC13 are natural next additions.
- [x] Create Ansible roles to improve repeatability of DevOps lab provisioning, reducing reliance on Vagrant provisioners — added under [`labs/infrastructure/devops-linux-lab/ansible/`](../../labs/infrastructure/devops-linux-lab/ansible/) (`common`, `docker`, `ssh_keys`, `devops_tools` roles); VM lifecycle, networking, and the stateful K3s bootstrap/join sequence remain in the Vagrantfile for now (see that directory's `README.md`).
- [x] Build a Windows Server hardening lab as a defensive counterpart to the Active Directory pentest lab — MVP in [`labs/security/windows-hardening/`](../../labs/security/windows-hardening/) (single hardened DC, `LAB_PROFILE=full` adds a domain-joined member server). Not yet at feature parity with the AD pentest lab (no AD CS, no LAPS, no Credential Guard, no Sysmon auto-install — see that lab's `docs/hardening-guide.md` §10 for the full list). Contributions toward closing that gap are welcome.
- [ ] Expand the VLAN lab with more realistic segmentation scenarios beyond the current five VLANs.

## Long-term / Exploratory

- [ ] Add an optional cloud deployment path using Terraform for either lab as an alternative to local libvirt. See [`docs/guides/optimization/minimal-resource-deployment.md`](../guides/optimization/minimal-resource-deployment.md).
- [ ] Build advanced Kubernetes security labs beyond the current Falco/Kyverno baseline, including supply chain attack scenarios and OPA Gatekeeper policies.
- [ ] Create a cross-lab scenario connecting the Active Directory pentest lab with the DevOps lab’s exposed services.

## Not Planned

- Multi-cloud parity (AWS/Azure/GCP simultaneously): the labs are designed around local KVM/libvirt as the primary environment. Cloud support, if added, would begin with a single provider rather than multiple.
- Windows-based host support: the tooling assumes a Linux host with Vagrant, libvirt, and KVM, so this is unlikely to change.

---

Have an idea not listed here? Open an issue or start a discussion — see [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

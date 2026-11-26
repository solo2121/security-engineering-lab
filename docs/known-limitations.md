# Known limitations

## Platform and resources

- Full-profile deployments may require 32 GB or more host RAM and approximately 200 GB or more free disk space, depending on the selected lab, provider, and deployment profile.
- KVM/QEMU with libvirt requires a compatible Linux host.
- VirtualBox support targets compatible Intel/AMD x86_64 hosts.
- Apple Silicon / ARM64 hosts have no currently supported deployment path.
- The project is designed primarily for a single-host laboratory architecture.

## Lab-specific limitations

- Windows-based labs use Microsoft evaluation media; users are responsible for complying with applicable Microsoft licensing terms.
- The Windows Server Hardening Lab is an experimental `v0.1.0` MVP with less real-world testing than the other labs.
- The Windows Server Hardening Lab does not yet cover AD CS hardening. LAPS, Sysmon with Windows Event Forwarding, and Credential Guard are available as opt-in, experimental controls (`HARDENING_ADVANCED=1`); see its [advanced controls guide](../labs/security/windows-hardening/docs/advanced-controls.md). See its [hardening guide](../labs/security/windows-hardening/docs/hardening-guide.md) for the complete list of known gaps.
- The LLM lab's prompt-injection filter is heuristic, and the offline mock model is deliberately gullible, so results with a real model (Ollama) will differ. The audit log and pending approvals are in memory, API keys are static, and the helpdesk agent runs against a snapshot of the lab's directory, not a live domain controller. See the [LLM lab README](../labs/security/active-directory/base/llm-lab/README.md) and its threat model.
- Ollama support is covered only by unit tests against a stubbed server; no real model runs in CI. CI builds and boots the LLM lab container, but a full `vagrant up llm01` is not run there.

## Dependencies and validation

- Third-party Vagrant boxes may change independently.
- CI validates repository quality and selected provider workflows but does not fully deploy every environment on every push. The one exception is the LLM lab container, which CI builds, boots with the compose hardening and smoke-tests on every push. No VM is booted in CI.

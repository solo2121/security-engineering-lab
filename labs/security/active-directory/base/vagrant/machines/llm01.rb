# VM definition: llm01
# Loaded by the Vagrantfile, which calls define_llm01(config).

def define_llm01(config)
  # ===========================================================================
  # LLM01 — OWASP Top 10 for LLM Applications (2025) training lab.
  # App lives in ./llm-lab; see llm-lab/README.md for full docs. The
  # provisioner below only stages files and runs setup — all vulnerable
  # behavior is sandboxed inside the app itself (llm-lab/app/safety.py).
  # ===========================================================================
  config.vm.define "llm01" do |vm|
    vm.vm.box = "generic/ubuntu2204"
    vm.vm.box_version = "4.3.10"
    vm.vm.hostname = "llm01"

    configure_network(vm, VM_IPS[:llm01])

    configure_provider(vm,
      memory: VM_MEMORY[:llm01],
      cpus: VM_CPUS[:llm01],
      disk_size: 100
    )

    vm.vm.synced_folder ".", "/vagrant", disabled: true
    vm.ssh.insert_key = true

    write_lab_hosts(vm)

    # The file provisioner runs as the unprivileged vagrant user, so the
    # app lands in a staging path first; the shell provisioner below moves
    # it into place under a dedicated, unprivileged service account.
    vm.vm.provision "file", source: "llm-lab", destination: "/tmp/llm-lab-src"

    vm.vm.provision "shell", name: "llm01-config", privileged: true, inline: render_provision("llm01/llm01-config.sh", LAB_SUBNET: LAB_SUBNET, LLM01_IP: VM_IPS[:llm01])
  end
end

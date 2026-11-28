#!/usr/bin/env python3
"""Tests for the DevOps lab's split Vagrantfile (vagrant/*.rb)."""

import re
from pathlib import Path

LAB = Path(__file__).resolve().parents[2] / "labs" / "infrastructure" / "devops-linux-lab"
VAGRANTFILE = LAB / "Vagrantfile"
ROLES = {"master", "worker", "lab", "kind", "k3d", "cicd"}


def _required() -> list[str]:
    text = VAGRANTFILE.read_text(encoding="utf-8")
    return re.findall(r"""^require_relative\s+['"](vagrant/[\w./-]+)['"]""", text, re.M)


def test_every_required_file_exists():
    required = _required()
    assert required
    for rel in required:
        assert (LAB / (rel + ".rb")).is_file(), f"{rel}.rb is required but missing"


def test_no_orphan_files_under_vagrant_dir():
    on_disk = {p.relative_to(LAB).as_posix() for p in (LAB / "vagrant").rglob("*.rb")}
    assert on_disk == {rel + ".rb" for rel in _required()}


def test_each_role_file_defines_its_function_and_machine_dispatches_to_it():
    machine = (LAB / "vagrant" / "machine.rb").read_text(encoding="utf-8")
    role_files = {p.stem for p in (LAB / "vagrant" / "roles").glob("*.rb")}
    assert role_files == ROLES
    for role in ROLES:
        text = (LAB / "vagrant" / "roles" / f"{role}.rb").read_text(encoding="utf-8")
        assert re.search(rf"^def provision_{role}\(", text, re.M)
        assert f"provision_{role}(" in machine


def test_vagrantfile_only_configures_and_delegates():
    text = VAGRANTFILE.read_text(encoding="utf-8")
    assert "configure_global(config)" in text
    assert "VMS_TO_START.each" in text and "define_vm(config, name, cfg)" in text
    assert "def " not in text, "helpers belong under vagrant/"


def test_load_order_puts_dependencies_first():
    required = _required()
    for earlier, later in [
        ("vagrant/provision", "vagrant/network"),
        ("vagrant/provider", "vagrant/network"),
        ("vagrant/network", "vagrant/harbor"),
        ("vagrant/harbor", "vagrant/cluster"),
        ("vagrant/cluster", "vagrant/machine"),
    ]:
        assert required.index(earlier) < required.index(later), f"{earlier} must load before {later}"


def test_no_file_uses_dir_to_find_the_lab_directory():
    # Inside vagrant/, __dir__ is the code folder, not the lab folder; use LAB_DIR.
    for path in (LAB / "vagrant").rglob("*.rb"):
        if path.name == "provision.rb":
            continue
        assert "__dir__" not in path.read_text(encoding="utf-8"), f"{path.name} should use LAB_DIR"


def test_enterprise_linux_boxes_are_overridable_and_default_to_release_10():
    settings = (LAB / "vagrant" / "settings.rb").read_text(encoding="utf-8")
    cluster = (LAB / "vagrant" / "cluster.rb").read_text(encoding="utf-8")
    machine = (LAB / "vagrant" / "machine.rb").read_text(encoding="utf-8")
    assert "ROCKY_BOX = ENV['ROCKY_BOX'] || 'rocky10'" in settings
    assert "ALMA_BOX = ENV['ALMA_BOX'] || 'almalinux/10'" in settings
    assert "Rocky-10-Vagrant-Libvirt.latest" in settings
    assert "Rocky-10-Vagrant-Vbox.latest" in settings
    assert '"rocky-lab" => { box: ROCKY_BOX, box_url: ROCKY_BOX_URL' in cluster
    assert '"alma-lab" => { box: ALMA_BOX' in cluster
    assert "vm.vm.box_url = cfg[:box_url] if cfg[:box_url]" in machine

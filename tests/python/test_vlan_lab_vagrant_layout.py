#!/usr/bin/env python3
"""Tests for the segmented AD lab's split Vagrantfile (vagrant/*.rb)."""

import re
from pathlib import Path

AD = Path(__file__).resolve().parents[2] / "labs" / "security" / "active-directory"
LAB = AD / "vlan-segmented"
VAGRANTFILE = LAB / "Vagrantfile"
VMS = {
    "opnsense": "opnsense",
    "dc01": "DC01",
    "kali": "kali",
    "ca01-esc": "CA01-ESC",
    "db01": "DB01",
    "win10": "WIN10",
    "print01": "print01",
    "llm01": "llm01",
    "cloud-pentest": "cloud-pentest",
    "juice-shop": "juice-shop",
}


def _required() -> list[str]:
    text = VAGRANTFILE.read_text(encoding="utf-8")
    return re.findall(r"""^require_relative\s+['"]([\w./-]+)['"]""", text, re.M)


def _target(rel: str) -> Path:
    return (LAB / (rel + ".rb")).resolve()


def test_every_required_file_exists():
    required = _required()
    assert required
    for rel in required:
        assert _target(rel).is_file(), f"{rel}.rb is required but missing"


def test_no_orphan_files_under_vagrant_dir():
    on_disk = {p.resolve() for p in (LAB / "vagrant").rglob("*.rb")}
    local = {_target(rel) for rel in _required() if rel.startswith("vagrant/")}
    assert on_disk == local


def test_provider_detection_is_shared_with_the_base_lab():
    shared = [rel for rel in _required() if not rel.startswith("vagrant/")]
    assert shared == ["../base/vagrant/provider_detect"]
    assert _target(shared[0]) == (AD / "base" / "vagrant" / "provider_detect.rb").resolve()


def test_each_vm_has_a_function_and_machine_dispatches_to_it():
    machine = (LAB / "vagrant" / "machine.rb").read_text(encoding="utf-8")
    assert {p.stem for p in (LAB / "vagrant" / "roles").glob("*.rb")} == set(VMS)
    for stem, vm_name in VMS.items():
        fn = "provision_" + stem.replace("-", "_")
        text = (LAB / "vagrant" / "roles" / f"{stem}.rb").read_text(encoding="utf-8")
        assert re.search(rf"^def {fn}\(", text, re.M)
        assert f"when '{vm_name}'" in machine and f"{fn}(" in machine


def test_vagrantfile_only_configures_and_delegates():
    text = VAGRANTFILE.read_text(encoding="utf-8")
    assert "configure_global(config)" in text and "define_vm(config, vm_name, vm_config)" in text
    assert "def " not in text, "helpers belong under vagrant/"


def test_load_order_puts_dependencies_first():
    required = _required()
    for earlier, later in [
        ("../base/vagrant/provider_detect", "vagrant/vm_config"),
        ("vagrant/provision", "vagrant/startup"),
        ("vagrant/profiles", "vagrant/vm_config"),
        ("vagrant/network", "vagrant/preflight"),
        ("vagrant/startup", "vagrant/providers"),
        ("vagrant/global", "vagrant/machine"),
        ("vagrant/machine", "vagrant/roles/opnsense"),
    ]:
        assert required.index(earlier) < required.index(later), f"{earlier} must load before {later}"


def test_provision_dir_resolves_to_the_lab_provision_folder():
    text = (LAB / "vagrant" / "provision.rb").read_text(encoding="utf-8")
    assert 'File.expand_path("../provision", __dir__)' in text
    assert (LAB / "provision").is_dir()

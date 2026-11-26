#!/usr/bin/env python3
"""Tests for the base lab's split Vagrantfile (vagrant/*.rb) and the manager that reads it."""

import importlib.util
import re
import sys
from pathlib import Path
from unittest import mock

PROJECT_ROOT = Path(__file__).resolve().parents[2]
LAB = PROJECT_ROOT / "labs" / "security" / "active-directory" / "base"
MANAGER_PATH = LAB / "scripts" / "vagrant_manager.py"

EXPECTED_VMS = [
    "kali",
    "dc01",
    "db01",
    "ca01-esc",
    "win10",
    "linux01",
    "print01",
    "llm01",
    "metasploitable2",
    "juice-shop",
    "cloud-pentest",
]


def _load_manager():
    # vagrant_manager.py needs the third-party "rich" package, which is not a
    # development dependency; fall back to a stub so these tests stay light.
    stubs = {}
    try:
        import rich.console  # noqa: F401
    except ImportError:
        for name in ("rich", "rich.console", "rich.panel", "rich.prompt", "rich.table", "rich.text"):
            stubs[name] = mock.MagicMock()
    with mock.patch.dict(sys.modules, stubs):
        spec = importlib.util.spec_from_file_location("base_vagrant_manager", MANAGER_PATH)
        module = importlib.util.module_from_spec(spec)
        sys.modules["base_vagrant_manager"] = module
        spec.loader.exec_module(module)
    return module


manager = _load_manager()
VAGRANTFILE = LAB / "Vagrantfile"


def _required_files() -> list[str]:
    text = VAGRANTFILE.read_text(encoding="utf-8")
    return re.findall(r"""^require_relative\s+['"](vagrant/[\w./-]+)['"]""", text, re.M)


def test_every_required_file_exists():
    required = _required_files()
    assert required, "the Vagrantfile should load its code from vagrant/"
    for rel in required:
        assert (LAB / (rel + ".rb")).is_file(), f"{rel}.rb is required but missing"


def test_no_orphan_files_under_vagrant_dir():
    required = {rel + ".rb" for rel in _required_files()}
    on_disk = {p.relative_to(LAB).as_posix() for p in (LAB / "vagrant").rglob("*.rb")}
    assert on_disk == required


def test_each_machine_file_defines_the_matching_function_and_is_called():
    text = VAGRANTFILE.read_text(encoding="utf-8")
    for machine in (LAB / "vagrant" / "machines").glob("*.rb"):
        fn = "define_" + machine.stem.replace("-", "_")
        assert f"def {fn}(config)" in machine.read_text(encoding="utf-8")
        assert f"{fn}(config)" in text


def test_manager_discovers_all_vms_in_definition_order():
    assert manager.discover_vms(VAGRANTFILE) == EXPECTED_VMS


def test_manager_reads_profiles_from_vagrant_dir():
    profiles = manager.parse_lab_profiles(VAGRANTFILE)
    assert profiles is not None
    assert set(profiles) == {"minimal", "ad", "web", "cloud", "llm", "full"}
    assert profiles["llm"] == ["llm01"]
    assert set(profiles["full"]) == set(EXPECTED_VMS) - {"kali", "dc01"}


def test_manager_still_reads_a_single_file_vagrantfile(tmp_path):
    vf = tmp_path / "Vagrantfile"
    vf.write_text(
        "LAB_PROFILES = {\n  'ad' => %w[web],\n}.freeze\nVagrant.configure('2') do |config|\n"
        '  config.vm.define "web" do |vm|\n  end\nend\n',
        encoding="utf-8",
    )
    assert manager.discover_vms(vf) == ["web"]
    assert manager.parse_lab_profiles(vf) == {"ad": ["web"]}


def test_manager_ignores_a_required_file_that_is_missing(tmp_path):
    vf = tmp_path / "Vagrantfile"
    vf.write_text("require_relative 'vagrant/gone'\nconfig.vm.define \"one\"\n", encoding="utf-8")
    assert manager.discover_vms(vf) == ["one"]

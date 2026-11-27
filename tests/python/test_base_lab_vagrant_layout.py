#!/usr/bin/env python3
"""Tests for the base lab's split Vagrantfile (vagrant/*.rb) and the manager that reads it."""

import json
import re
import subprocess
import sys
from pathlib import Path

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


# The manager imports the third-party "rich" package, which is not a development
# dependency, so it runs in a subprocess with "rich" stubbed out. That also keeps
# this large script out of the in-process coverage figure, as before this test.
_MANAGER_SNIPPET = """
import importlib.util, json, sys
from pathlib import Path
from unittest import mock

stubs = {n: mock.MagicMock() for n in ("rich", "rich.console", "rich.panel", "rich.prompt", "rich.table", "rich.text")}
with mock.patch.dict(sys.modules, stubs):
    spec = importlib.util.spec_from_file_location("lab_manager", sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    sys.modules["lab_manager"] = module
    spec.loader.exec_module(module)
vagrantfile = Path(sys.argv[2])
print(json.dumps({"vms": module.discover_vms(vagrantfile), "profiles": module.parse_lab_profiles(vagrantfile)}))
"""


def _manager_view(vagrantfile: Path) -> dict:
    result = subprocess.run(
        [sys.executable, "-I", "-c", _MANAGER_SNIPPET, str(MANAGER_PATH), str(vagrantfile)],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return json.loads(result.stdout.strip().splitlines()[-1])


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
    assert _manager_view(VAGRANTFILE)["vms"] == EXPECTED_VMS


def test_manager_reads_profiles_from_vagrant_dir():
    profiles = _manager_view(VAGRANTFILE)["profiles"]
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
    assert _manager_view(vf) == {"vms": ["web"], "profiles": {"ad": ["web"]}}


def test_manager_ignores_a_required_file_that_is_missing(tmp_path):
    vf = tmp_path / "Vagrantfile"
    vf.write_text("require_relative 'vagrant/gone'\nconfig.vm.define \"one\"\n", encoding="utf-8")
    assert _manager_view(vf)["vms"] == ["one"]

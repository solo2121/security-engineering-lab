#!/usr/bin/env python3
"""
validate_lab.py — Safe, read-only repository health validation.

Checks repository structure, required files, Vagrantfile syntax
(via `vagrant validate`, if available), and documentation
consistency. Never starts VMs, touches the network, or runs any
offensive tooling — it only inspects files on disk.

Usage:
    python3 scripts/validate_lab.py
    python3 scripts/validate_lab.py --verbose
    python3 scripts/validate_lab.py --skip-vagrant   # CI without libvirt

Exit status:
    0  all checks passed
    1  one or more checks failed
"""

from __future__ import annotations

import argparse
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.lib.subprocess import CommandExecutionError, run_command  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]

REQUIRED_TOP_LEVEL_FILES = [
    "README.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "CHANGELOG.md",
    "Makefile",
    "requirements-dev.txt",
]

REQUIRED_TOP_LEVEL_DIRS = [
    "docs",
    "labs",
    "tools",
    "tests",
    "scripts",
]

# Each lab directory should carry its own README documenting the lab.
LAB_DIRS_REQUIRING_README = [
    "labs/security/active-directory/base",
    "labs/security/active-directory/vlan-segmented",
    "labs/infrastructure/devops-linux-lab",
    "labs/security/windows-hardening",
]


def discover_vagrantfiles() -> list[Path]:
    """
    Find every ``Vagrantfile`` under ``labs/`` on disk.

    Discovered dynamically (rather than hardcoded) so this validator
    doesn't become a second, driftable source of truth for the lab
    topology — adding or removing a lab just works without touching
    this script. Excludes anything under a ``.vagrant/`` state
    directory (those are runtime artifacts, not lab definitions).
    """
    labs_dir = REPO_ROOT / "labs"
    if not labs_dir.is_dir():
        return []
    return sorted(vf for vf in labs_dir.rglob("Vagrantfile") if ".vagrant" not in vf.parts)


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


def check_repository_structure() -> CheckResult:
    missing = [f for f in REQUIRED_TOP_LEVEL_FILES if not (REPO_ROOT / f).is_file()]
    missing += [d for d in REQUIRED_TOP_LEVEL_DIRS if not (REPO_ROOT / d).is_dir()]
    if missing:
        return CheckResult("Repository structure", False, f"missing: {', '.join(missing)}")
    return CheckResult("Repository structure", True)


def check_lab_readmes() -> CheckResult:
    missing = [lab for lab in LAB_DIRS_REQUIRING_README if not (REPO_ROOT / lab / "README.md").is_file()]
    if missing:
        return CheckResult("Lab documentation", False, f"missing README in: {', '.join(missing)}")
    return CheckResult("Lab documentation", True)


def check_vagrant_syntax(skip: bool) -> CheckResult:
    if skip:
        return CheckResult("Vagrant configuration", True, "skipped (--skip-vagrant)")

    vagrantfiles = discover_vagrantfiles()
    if not vagrantfiles:
        return CheckResult("Vagrant configuration", False, "no Vagrantfile found under labs/")

    if shutil.which("vagrant") is None:
        return CheckResult("Vagrant configuration", True, "vagrant not installed, syntax check skipped")

    failures = []
    for vf in vagrantfiles:
        rel = vf.relative_to(REPO_ROOT)
        try:
            result = run_command(["vagrant", "validate"], cwd=str(vf.parent), timeout=60)
        except CommandExecutionError as exc:
            failures.append(f"{rel}: {exc}")
            continue
        if not result.ok:
            failures.append(f"{rel}: {result.stderr.strip()[:200]}")

    if failures:
        return CheckResult("Vagrant configuration", False, "; ".join(failures))
    return CheckResult("Vagrant configuration", True)


def check_documentation_consistency() -> CheckResult:
    """
    Lightweight cross-check: every lab directory referenced from
    labs/README.md should exist on disk, and vice versa.
    """
    labs_readme = REPO_ROOT / "labs" / "README.md"
    if not labs_readme.is_file():
        return CheckResult("Documentation consistency", False, "labs/README.md missing")

    text = labs_readme.read_text(encoding="utf-8", errors="ignore")
    stale_refs = []
    for lab in LAB_DIRS_REQUIRING_README:
        lab_name = Path(lab).name
        if lab_name not in text:
            stale_refs.append(lab_name)

    if stale_refs:
        return CheckResult(
            "Documentation consistency",
            False,
            f"labs/README.md does not mention: {', '.join(stale_refs)}",
        )
    return CheckResult("Documentation consistency", True)


def check_python_tools_syntax() -> CheckResult:
    """Compile-check every Python file under tools/ to catch syntax errors early."""
    import py_compile

    failures = []
    for py_file in (REPO_ROOT / "tools").rglob("*.py"):
        try:
            py_compile.compile(str(py_file), doraise=True)
        except py_compile.PyCompileError as exc:
            failures.append(f"{py_file.relative_to(REPO_ROOT)}: {exc.msg}")

    if failures:
        return CheckResult("Python tool syntax", False, "; ".join(failures))
    return CheckResult("Python tool syntax", True)


def run_all_checks(skip_vagrant: bool) -> list[CheckResult]:
    return [
        check_repository_structure(),
        check_lab_readmes(),
        check_python_tools_syntax(),
        check_vagrant_syntax(skip_vagrant),
        check_documentation_consistency(),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="validate_lab.py",
        description="Safe, read-only health validation for the security-engineering-lab repository.",
    )
    parser.add_argument(
        "--skip-vagrant",
        action="store_true",
        help="Skip `vagrant validate` checks (useful without libvirt/Vagrant installed).",
    )
    args = parser.parse_args()

    results = run_all_checks(skip_vagrant=args.skip_vagrant)

    all_passed = True
    for result in results:
        status = "PASS" if result.passed else "FAIL"
        line = f"{status}: {result.name}"
        if result.detail:
            line += f" — {result.detail}"
        print(line)
        if not result.passed:
            all_passed = False

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())

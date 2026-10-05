"""Static validation for the Windows hardening lab's advanced controls.

These tests cannot boot Windows guests. They guard the things that can be
checked on any host: files exist, XML is well formed, scripts are ASCII-only
(Windows PowerShell 5.1 misreads BOM-less UTF-8), scripts fail fast, and no
credentials are hard-coded.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET  # nosec B405 - parsing repository-owned files only
from pathlib import Path

import pytest

LAB = Path(__file__).resolve().parents[1] / "labs" / "security" / "windows-hardening"
ADV = LAB / "provision" / "advanced"
CONFIG = ADV / "config"

EXPECTED_SCRIPTS = [
    "01-Move-To-LabOu.ps1",
    "02-Enable-WindowsLaps-DC.ps1",
    "03-Apply-And-Verify-Laps.ps1",
    "10-Install-Sysmon.ps1",
    "11-Setup-WefCollector.ps1",
    "12-Configure-WefSource.ps1",
    "13-Test-Wef.ps1",
    "20-Enable-CredentialGuard.ps1",
    "21-Test-CredentialGuard.ps1",
]

SCRIPT_PATHS = [ADV / name for name in EXPECTED_SCRIPTS]


@pytest.mark.parametrize("path", SCRIPT_PATHS, ids=EXPECTED_SCRIPTS)
def test_script_exists_and_is_ascii(path: Path) -> None:
    assert path.is_file(), f"missing {path}"
    path.read_bytes().decode("ascii")


@pytest.mark.parametrize("path", SCRIPT_PATHS, ids=EXPECTED_SCRIPTS)
def test_script_fails_fast(path: Path) -> None:
    text = path.read_text(encoding="ascii")
    assert "$ErrorActionPreference = 'Stop'" in text
    assert "Set-StrictMode -Version Latest" in text


@pytest.mark.parametrize("path", SCRIPT_PATHS, ids=EXPECTED_SCRIPTS)
def test_script_has_no_hardcoded_secret(path: Path) -> None:
    text = path.read_text(encoding="ascii")
    literal = re.compile(r"(?i)(password|secret|token)\w*\s*=\s*['\"][^'\"\s]+['\"]")
    assert not literal.search(text), f"possible hard-coded credential in {path.name}"


def test_sysmon_baseline_is_well_formed() -> None:
    root = ET.parse(CONFIG / "sysmon-lab-baseline.xml").getroot()  # nosec B314
    assert root.tag == "Sysmon"
    assert root.get("schemaversion")
    assert root.find("EventFiltering") is not None


def test_wef_subscription_is_source_initiated_and_covers_sysmon() -> None:
    ns = {"s": "http://schemas.microsoft.com/2006/03/windows/events/subscription"}
    root = ET.parse(CONFIG / "wef-subscription.xml").getroot()  # nosec B314
    assert root.findtext("s:SubscriptionType", namespaces=ns) == "SourceInitiated"
    assert root.findtext("s:SubscriptionId", namespaces=ns) == "LabBaseline"
    query = root.findtext("s:Query", namespaces=ns) or ""
    assert "Microsoft-Windows-Sysmon/Operational" in query
    ET.fromstring(query.strip())  # nosec B314 - the embedded QueryList must be valid XML too


def test_vagrant_helper_is_opt_in_and_reads_secrets_from_env() -> None:
    text = (ADV / "vagrant_advanced.rb").read_text(encoding="utf-8")
    assert 'flag?("HARDENING_ADVANCED"' in text
    assert 'settings.fetch(:admin_password)' in text
    for name in EXPECTED_SCRIPTS:
        assert name in text, f"{name} is not wired into vagrant_advanced.rb"


def test_documentation_exists() -> None:
    doc = LAB / "docs" / "advanced-controls.md"
    assert doc.is_file()
    assert "Credential Guard" in doc.read_text(encoding="utf-8")


def test_vagrantfile_is_wired_to_the_helper() -> None:
    text = (LAB / "Vagrantfile").read_text(encoding="utf-8")
    assert re.search(r"require_relative ['\"]provision/advanced/vagrant_advanced['\"]", text)
    assert "AdvancedControls.apply_dc(" in text
    assert "AdvancedControls.apply_member(" in text

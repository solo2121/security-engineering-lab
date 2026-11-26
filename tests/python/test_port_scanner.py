#!/usr/bin/env python3
"""
Unit tests for the advanced Python port scanner.

Validates:
- module loading
- ScanType enum
- ScanResult structure
- argparse behavior

The scanner lives at:

tools/security/reconnaissance/port-scanner.py
"""

import importlib.util
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]

PORT_SCANNER_PATH = PROJECT_ROOT / "tools" / "security" / "reconnaissance" / "port-scanner.py"


def _load_module():
    """
    Dynamically load port-scanner.py.

    Required because the filename contains a hyphen.
    """

    if not PORT_SCANNER_PATH.exists():
        raise FileNotFoundError(f"Port scanner not found: {PORT_SCANNER_PATH}")

    spec = importlib.util.spec_from_file_location(
        "port_scanner",
        PORT_SCANNER_PATH,
    )

    module = importlib.util.module_from_spec(spec)

    sys.modules["port_scanner"] = module

    spec.loader.exec_module(module)

    return module


@pytest.fixture(scope="module")
def scanner():
    return _load_module()


def test_module_loads_without_side_effects(scanner):
    assert scanner is not None


def test_scan_type_enum_has_expected_members(scanner):
    assert hasattr(scanner, "ScanType")

    members = scanner.ScanType.__members__

    assert "TCP_CONNECT" in members
    assert "TCP_SYN" in members
    assert "UDP" in members


def test_scan_result_defaults(scanner):
    result = scanner.ScanResult(
        port=80,
        is_open=True,
        scan_type=scanner.ScanType.TCP_CONNECT,
    )

    assert result.port == 80
    assert result.is_open is True
    assert result.scan_type == scanner.ScanType.TCP_CONNECT
    assert result.response_time == 0.0
    assert result.error is None
    assert result.banner is None
    assert result.target == ""


def test_scan_result_is_immutable(scanner):
    result = scanner.ScanResult(
        port=22,
        is_open=True,
        scan_type=scanner.ScanType.TCP_CONNECT,
    )

    with pytest.raises(AttributeError):
        result.port = 443


@pytest.mark.parametrize(
    "argv,target,ports",
    [
        (
            ["scanner.py", "10.0.0.5", "-p", "22,80,443"],
            "10.0.0.5",
            "22,80,443",
        ),
        (
            ["scanner.py", "scanme.example.com", "-p", "1-1024"],
            "scanme.example.com",
            "1-1024",
        ),
    ],
)
def test_parse_args_target_and_ports(
    scanner,
    monkeypatch,
    argv,
    target,
    ports,
):
    monkeypatch.setattr(sys, "argv", argv)

    args = scanner.parse_args()

    assert args.target == target
    assert args.ports == ports


def test_parse_args_defaults_when_no_target(scanner, monkeypatch):
    monkeypatch.setattr(
        sys,
        "argv",
        ["scanner.py"],
    )

    args = scanner.parse_args()

    assert args.target is None
    assert args.ports is None


def test_parse_args_syn_flag_sets_scan_type(scanner, monkeypatch):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "scanner.py",
            "10.0.0.5",
            "-p",
            "80",
            "--syn",
        ],
    )

    args = scanner.parse_args()

    assert args.scan_type == scanner.ScanType.TCP_SYN


def test_parse_args_udp_flag_sets_scan_type(scanner, monkeypatch):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "scanner.py",
            "10.0.0.5",
            "-p",
            "53",
            "--udp",
        ],
    )

    args = scanner.parse_args()

    assert args.scan_type == scanner.ScanType.UDP

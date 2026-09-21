#!/usr/bin/env python3
"""
Unit tests for the tcpdump wrapper.

The wrapper lives at:

tools/security/network/tcpdump-wrapper.py

Covers:
- parsing of `tcpdump -D` output (index and name are joined by a dot)
- input validation for ports, hosts, packet counts, and custom filters
- construction of the final tcpdump argv (options before the BPF filter)
"""

import importlib.util
import sys
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[2]

WRAPPER_PATH = PROJECT_ROOT / "tools" / "security" / "network" / "tcpdump-wrapper.py"

# Captured from tcpdump 4.99.4 / libpcap 1.10.4 (Ubuntu 24.04).
TCPDUMP_D_MODERN = (
    "1.eth0 [Up, Running, Connected]\n"
    "2.any (Pseudo-device that captures on all interfaces) [Up, Running]\n"
    "3.lo [Up, Running, Loopback]\n"
    "4.ifb0 [none]\n"
)

# Older releases print only the index and name.
TCPDUMP_D_LEGACY = "1.eth0\n2.lo\n"


def _load_module():
    """Dynamically load tcpdump-wrapper.py (the filename contains a hyphen)."""
    spec = importlib.util.spec_from_file_location("tcpdump_wrapper", WRAPPER_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["tcpdump_wrapper"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def wrapper():
    return _load_module()


@pytest.fixture
def scripted_input(monkeypatch, wrapper):
    """Feed a fixed sequence of answers to input() and silence screen clearing."""

    def _install(*answers):
        feed = iter(answers)
        monkeypatch.setattr("builtins.input", lambda _prompt="": next(feed))
        monkeypatch.setattr(wrapper, "clear_screen", lambda: None)

    return _install


# ---------------------------------------------------------------------------
# Interface parsing
# ---------------------------------------------------------------------------
def test_parse_interface_list_modern_format(wrapper):
    assert wrapper.parse_interface_list(TCPDUMP_D_MODERN) == ["eth0", "any", "lo", "ifb0"]


def test_parse_interface_list_legacy_format(wrapper):
    assert wrapper.parse_interface_list(TCPDUMP_D_LEGACY) == ["eth0", "lo"]


def test_parse_interface_list_ignores_blank_and_unrelated_lines(wrapper):
    assert wrapper.parse_interface_list("\n\nnot an interface line\n1.eth0\n") == ["eth0"]


def test_parse_interface_list_empty(wrapper):
    assert wrapper.parse_interface_list("") == []


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------
def test_build_command_puts_filter_last(wrapper):
    cmd = wrapper.build_command("eth0", "/tmp/out.pcap", ["port 443"], ["-c", "10"])
    assert cmd == ["tcpdump", "-i", "eth0", "-w", "/tmp/out.pcap", "-c", "10", "port 443"]


def test_build_command_without_filter_or_count(wrapper):
    assert wrapper.build_command("lo", "/tmp/x.pcap", [], []) == ["tcpdump", "-i", "lo", "-w", "/tmp/x.pcap"]


# ---------------------------------------------------------------------------
# Prompt validation
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("bad", ["", "abc", "0", "65536", "-1", "80; id", "8 0"])
def test_prompt_port_rejects_invalid_then_accepts_valid(wrapper, scripted_input, bad):
    scripted_input(bad, "443")
    assert wrapper.prompt_port() == 443


@pytest.mark.parametrize("value", ["192.168.1.10", "::1", "example.com", "lab-host.local"])
def test_prompt_host_accepts_ip_and_hostname(wrapper, scripted_input, value):
    scripted_input(value)
    assert wrapper.prompt_host() == value


@pytest.mark.parametrize("bad", ["", "8.8.8.8; rm -rf /", "host with spaces", "-i eth0", "a$b"])
def test_prompt_host_rejects_unsafe_input(wrapper, scripted_input, bad):
    scripted_input(bad, "10.0.0.1")
    assert wrapper.prompt_host() == "10.0.0.1"


@pytest.mark.parametrize("bad", ["", "-z /tmp/evil.sh", "--help"])
def test_prompt_custom_filter_rejects_empty_and_option_like_input(wrapper, scripted_input, bad):
    scripted_input(bad, "tcp and port 80")
    assert wrapper.prompt_custom_filter() == "tcp and port 80"


@pytest.mark.parametrize("bad", ["", "abc", "0", "-5", "1.5"])
def test_prompt_positive_int_rejects_invalid(wrapper, scripted_input, bad):
    scripted_input(bad, "25")
    assert wrapper.prompt_positive_int("n: ") == 25


# ---------------------------------------------------------------------------
# Menu flows
# ---------------------------------------------------------------------------
def test_select_capture_options_protocol_reprompts_instead_of_crashing(wrapper, scripted_input):
    # "abc" and "9" previously raised ValueError / silently fell back to tcp.
    scripted_input("4", "abc", "9", "2")
    assert wrapper.select_capture_options() == ["udp"]


def test_select_capture_options_port_and_host(wrapper, scripted_input):
    scripted_input("2", "8080")
    assert wrapper.select_capture_options() == ["port 8080"]
    scripted_input("3", "10.0.0.5")
    assert wrapper.select_capture_options() == ["host 10.0.0.5"]


def test_select_capture_options_basic_and_invalid_choice(wrapper, scripted_input):
    scripted_input("x", "1")
    assert wrapper.select_capture_options() == []


def test_select_packet_count(wrapper, scripted_input):
    scripted_input("1")
    assert wrapper.select_packet_count() == []
    scripted_input("2", "abc", "50")
    assert wrapper.select_packet_count() == ["-c", "50"]

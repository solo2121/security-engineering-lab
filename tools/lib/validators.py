"""
Input validation helpers shared across security tooling.

These validators exist to give consistent, testable, non-network-facing
checks on user-supplied input (targets, ports, files) before a tool
acts on it. They deliberately do not perform any network I/O
themselves (no DNS resolution, no connection attempts) — that keeps
them fast, side-effect-free, and easy to unit test.
"""

from __future__ import annotations

import ipaddress
import re
from pathlib import Path

_HOSTNAME_RE = re.compile(r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)" r"(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$")


def is_valid_ip(value: str) -> bool:
    """Return True if ``value`` is a valid IPv4 or IPv6 address."""
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def is_valid_network(value: str) -> bool:
    """Return True if ``value`` is a valid IPv4/IPv6 network (CIDR notation)."""
    try:
        ipaddress.ip_network(value, strict=False)
        return True
    except ValueError:
        return False


def is_valid_hostname(value: str) -> bool:
    """Return True if ``value`` looks like a syntactically valid hostname."""
    if not value:
        return False
    return bool(_HOSTNAME_RE.match(value))


def is_valid_target(value: str) -> bool:
    """
    Return True if ``value`` is a valid scan/audit target.

    A "target" may be an IP address, a CIDR network, or a hostname.
    This is a syntax check only — it does not verify the target is
    reachable or in-scope. Callers are responsible for enforcing lab
    scope boundaries (see docs/architecture/security-scope.md).
    """
    return is_valid_ip(value) or is_valid_network(value) or is_valid_hostname(value)


def is_valid_port(value: int | str) -> bool:
    """Return True if ``value`` is an integer (or numeric string) in [1, 65535]."""
    try:
        port = int(value)
    except (TypeError, ValueError):
        return False
    return 1 <= port <= 65535


def parse_port_range(value: str) -> list[int]:
    """
    Parse a port specification into a sorted list of unique ports.

    Accepts comma-separated ports and/or hyphenated ranges, e.g.
    ``"22,80,443"`` or ``"1-1024"`` or ``"22,80,1000-1010"``.

    Raises:
        ValueError: If any component is not a valid port or range.
    """
    ports: set[int] = set()
    for chunk in value.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            start_str, _, end_str = chunk.partition("-")
            start, end = int(start_str), int(end_str)
            if not (is_valid_port(start) and is_valid_port(end)) or start > end:
                raise ValueError(f"invalid port range: {chunk!r}")
            ports.update(range(start, end + 1))
        else:
            port = int(chunk)
            if not is_valid_port(port):
                raise ValueError(f"invalid port: {chunk!r}")
            ports.add(port)
    return sorted(ports)


def is_existing_file(value: str) -> bool:
    """Return True if ``value`` is a path to an existing, readable file."""
    path = Path(value)
    return path.is_file()

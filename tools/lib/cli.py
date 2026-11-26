"""
Shared argparse scaffolding and dependency-check helpers for CLI tools.

Goals:
- Give every tool a consistent ``--verbose/--quiet`` flag pair and
  ``--help`` epilog with a usage example, without copy-pasting the
  same argparse boilerplate into each script.
- Provide a single, testable way to check for required third-party
  Python packages or external binaries before a tool proceeds, with a
  clear error message instead of a raw ``ImportError`` or ``OSError``.
"""

from __future__ import annotations

import argparse
import importlib.util
import shutil
import sys
from dataclasses import dataclass


@dataclass
class MissingDependency:
    """Describes a single missing dependency for a clear error message."""

    name: str
    kind: str  # "python" or "binary"
    install_hint: str = ""


def build_parser(
    prog: str,
    description: str,
    epilog_examples: list[str] | None = None,
) -> argparse.ArgumentParser:
    """
    Create an ArgumentParser pre-populated with common flags.

    Adds ``-v/--verbose`` and ``-q/--quiet`` (mutually exclusive) so
    every tool supports the same logging controls. Callers add their
    own tool-specific arguments after calling this.

    Args:
        prog: Program name shown in ``--help`` (typically the script's
            filename, e.g. "port-scanner.py").
        description: One-line description of what the tool does.
        epilog_examples: Optional list of example invocation strings,
            rendered under an "Examples:" heading in ``--help``.

    Returns:
        A configured ``argparse.ArgumentParser``.
    """
    epilog = ""
    if epilog_examples:
        examples = "\n".join(f"  {example}" for example in epilog_examples)
        epilog = f"Examples:\n{examples}"

    parser = argparse.ArgumentParser(
        prog=prog,
        description=description,
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    verbosity = parser.add_mutually_exclusive_group()
    verbosity.add_argument("-v", "--verbose", action="store_true", help="Enable debug-level logging.")
    verbosity.add_argument("-q", "--quiet", action="store_true", help="Suppress informational output.")

    return parser


def check_dependencies(
    python_packages: list[str] | None = None,
    binaries: list[str] | None = None,
) -> list[MissingDependency]:
    """
    Check that required Python packages and/or external binaries exist.

    This does not raise — it returns a list so callers can decide
    whether a missing dependency is fatal or just degrades a feature.

    Args:
        python_packages: Importable module names to check for
            (e.g. ``["scapy", "requests"]``).
        binaries: Executable names to check for on ``PATH``
            (e.g. ``["nmap", "tcpdump"]``).

    Returns:
        A list of :class:`MissingDependency`, empty if everything is
        available.
    """
    missing: list[MissingDependency] = []

    for package in python_packages or []:
        if importlib.util.find_spec(package) is None:
            missing.append(
                MissingDependency(
                    name=package,
                    kind="python",
                    install_hint=f"pip install {package}",
                )
            )

    for binary in binaries or []:
        if shutil.which(binary) is None:
            missing.append(
                MissingDependency(
                    name=binary,
                    kind="binary",
                    install_hint=f"install '{binary}' via your OS package manager",
                )
            )

    return missing


def require_dependencies(
    python_packages: list[str] | None = None,
    binaries: list[str] | None = None,
    exit_on_missing: bool = True,
) -> bool:
    """
    Check dependencies and print a clear error if any are missing.

    Args:
        python_packages: See :func:`check_dependencies`.
        binaries: See :func:`check_dependencies`.
        exit_on_missing: If True (default), call ``sys.exit(1)`` when
            dependencies are missing. Set False in tests to just get a
            boolean back.

    Returns:
        True if all dependencies are present, False otherwise (only
        reachable when ``exit_on_missing`` is False).
    """
    missing = check_dependencies(python_packages, binaries)
    if not missing:
        return True

    print("Missing required dependencies:", file=sys.stderr)
    for dep in missing:
        print(f"  - [{dep.kind}] {dep.name} ({dep.install_hint})", file=sys.stderr)

    if exit_on_missing:
        sys.exit(1)
    return False

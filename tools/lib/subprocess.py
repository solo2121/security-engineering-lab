"""
Safe subprocess execution helpers for CLI tools.

The tools in this repo frequently shell out to external utilities
(``nmap``, ``tcpdump``, ``amass``, ``vagrant``, etc.). This module
centralizes that so every call:

- never uses ``shell=True`` (avoids shell-injection footguns),
- has an explicit, sane default timeout,
- returns a small structured result instead of raising on non-zero
  exit by default (many of these tools intentionally check return
  codes rather than treating them as fatal errors),
- produces one consistent exception type for genuine execution
  failures (binary not found, timeout).
"""

from __future__ import annotations

import subprocess  # noqa: S404 — this module IS the vetted wrapper
from dataclasses import dataclass


class CommandExecutionError(RuntimeError):
    """Raised when a command cannot be executed at all (not merely a non-zero exit)."""


@dataclass
class CommandResult:
    """Structured result of a subprocess invocation."""

    args: list[str]
    returncode: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        """True if the command exited with status 0."""
        return self.returncode == 0


def run_command(
    args: list[str],
    *,
    timeout: float = 30.0,
    check: bool = False,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
) -> CommandResult:
    """
    Run an external command safely and capture its output.

    Args:
        args: Command and arguments as a list (never a shell string).
        timeout: Seconds to wait before killing the process and
            raising :class:`CommandExecutionError`.
        check: If True, raise :class:`CommandExecutionError` on a
            non-zero exit code in addition to the timeout/not-found
            cases. Defaults to False because several tools in this
            repo (scanners, audit scripts) treat non-zero exits as
            meaningful results, not failures.
        cwd: Optional working directory for the command.
        env: Optional environment variables (replaces the inherited
            environment entirely if provided).

    Returns:
        A :class:`CommandResult` with captured stdout/stderr.

    Raises:
        CommandExecutionError: If the binary doesn't exist, the
            command times out, or (when ``check=True``) it exits
            non-zero.
    """
    if not args:
        raise ValueError("args must contain at least the command name")

    try:
        completed = subprocess.run(  # noqa: S603 — args is a list, never shell=True
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env=env,
            check=False,
        )
    except FileNotFoundError as exc:
        raise CommandExecutionError(f"command not found: {args[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise CommandExecutionError(f"command timed out after {timeout}s: {' '.join(args)}") from exc

    result = CommandResult(
        args=args,
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )

    if check and not result.ok:
        raise CommandExecutionError(f"command exited {result.returncode}: {' '.join(args)}\n{result.stderr}")

    return result

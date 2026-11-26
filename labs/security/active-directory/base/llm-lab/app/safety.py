"""
Shared safety controls used by every scenario router.

Design principle: scenarios are allowed to *demonstrate* a vulnerability
class, but every action that would be dangerous in a real deployment is
intercepted here and replaced with a sandboxed, logged, non-destructive
equivalent. No scenario module calls a shell, opens an arbitrary path, or
installs a package directly — they all go through these helpers instead.
"""

from __future__ import annotations

import logging
import re
import time
from collections import defaultdict, deque
from pathlib import Path
from typing import Deque, Dict

from fastapi import HTTPException

from app import config

logger = logging.getLogger("llm_lab.safety")

# ---------------------------------------------------------------------------
# Command simulation (LLM01 / LLM06 / LLM08 "excessive agency" demos)
# ---------------------------------------------------------------------------
# Deterministic, hardcoded outputs for the fixed allowlist in config.py.
# Nothing here ever touches subprocess, os.system, eval, or a real shell.
_SIMULATED_COMMAND_OUTPUT = {
    "id": "uid=1000(lab-sandbox) gid=1000(lab-sandbox) groups=1000(lab-sandbox)",
    "whoami": "lab-sandbox",
    "pwd": str(config.SANDBOX_DIR),
    "uname": "Linux llm01 5.15.0-lab #1 SMP x86_64 GNU/Linux (simulated)",
}


def simulate_command(raw_command: str) -> dict:
    """
    Simulate execution of an operator-supplied "command" string without ever
    running a real process. Only the fixed allowlist in config.ALLOWED_COMMANDS
    is recognized; anything else — including shell metacharacters, chained
    commands, or destructive commands such as `rm -rf /` — is rejected and
    logged, never executed or forwarded to a shell.
    """
    command = (raw_command or "").strip()
    base = command.split()[0] if command else ""

    if base not in config.ALLOWED_COMMANDS:
        logger.warning("blocked_command", extra={"attempted_command": command})
        return {
            "executed": False,
            "reason": (
                f"'{base or command}' is not on the allowlist "
                f"({sorted(config.ALLOWED_COMMANDS)}). No process was started; "
                "this call never reaches a real shell."
            ),
        }

    if base == "echo":
        # Echo is allowed but still fully simulated: we just reflect the
        # remaining text, we don't hand it to /bin/echo via a shell.
        text = command[len("echo") :].strip()
        return {"executed": True, "simulated": True, "output": text[: config.MAX_OUTPUT_LENGTH]}

    return {"executed": True, "simulated": True, "output": _SIMULATED_COMMAND_OUTPUT[base]}


# ---------------------------------------------------------------------------
# Sandboxed file access (LLM02 / LLM06 "arbitrary file read" demos)
# ---------------------------------------------------------------------------
def resolve_sandbox_path(user_path: str) -> Path:
    """
    Resolve a user-supplied path strictly inside data/sandbox. Any attempt to
    escape the sandbox (absolute paths, `..`, symlinks pointing outside)
    raises HTTP 400 rather than being silently reinterpreted as "safe" —
    that reinterpretation is itself the bug this scenario teaches about.
    """
    candidate = (config.SANDBOX_DIR / user_path.lstrip("/")).resolve()
    try:
        candidate.relative_to(config.SANDBOX_DIR.resolve())
    except ValueError:
        logger.warning("blocked_path_traversal", extra={"attempted_path": user_path})
        raise HTTPException(
            status_code=400,
            detail=(
                "Path escapes the lab sandbox (data/sandbox/). "
                "In a real deployment this request would have read an "
                "arbitrary file; here it is refused and logged instead."
            ),
        )
    return candidate


# ---------------------------------------------------------------------------
# Redaction (LLM02 / LLM07 — sensitive info / system-prompt disclosure)
# ---------------------------------------------------------------------------
_SECRET_PATTERN = re.compile(r"(FAKE-ONLY-[A-Za-z0-9\-]+|LAB_SECRET_[A-Z0-9_]+|SYNTHETIC-[A-Za-z0-9\-]+)")


def redact(text: str) -> str:
    """Replace synthetic secret markers with a redaction placeholder."""
    return _SECRET_PATTERN.sub("[REDACTED]", text)


def is_synthetic_marker(value: str) -> bool:
    return any(value.startswith(prefix) for prefix in config.SYNTHETIC_MARKER_PREFIXES)


# ---------------------------------------------------------------------------
# Output encoding (LLM05 — improper output handling)
# ---------------------------------------------------------------------------
_HTML_ESCAPES = {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#x27;"}
_HTML_ESCAPE_RE = re.compile("|".join(re.escape(c) for c in _HTML_ESCAPES))


def html_encode(text: str) -> str:
    return _HTML_ESCAPE_RE.sub(lambda m: _HTML_ESCAPES[m.group(0)], text)


# ---------------------------------------------------------------------------
# Bounded input helpers (LLM10 — unbounded consumption)
# ---------------------------------------------------------------------------
def enforce_text_limit(text: str, field: str = "input") -> str:
    if text is None:
        return ""
    if len(text) > config.MAX_TEXT_LENGTH:
        logger.info("input_truncated_rejected", extra={"field": field, "length": len(text)})
        raise HTTPException(
            status_code=413,
            detail=f"'{field}' exceeds the {config.MAX_TEXT_LENGTH}-character lab limit.",
        )
    return text


# ---------------------------------------------------------------------------
# In-memory rate limiter — per client IP, fixed window via deque of
# timestamps. Good enough for a single-process teaching lab; not intended
# for production use.
# ---------------------------------------------------------------------------
_request_log: Dict[str, Deque[float]] = defaultdict(deque)
_daily_quota_log: Dict[str, int] = defaultdict(int)
_daily_quota_day: Dict[str, int] = defaultdict(int)


def check_rate_limit(client_id: str) -> None:
    now = time.time()
    window_start = now - config.RATE_LIMIT_WINDOW_SECONDS
    log = _request_log[client_id]
    while log and log[0] < window_start:
        log.popleft()
    if len(log) >= config.RATE_LIMIT_REQUESTS:
        logger.info("rate_limited", extra={"client_id": client_id})
        raise HTTPException(
            status_code=429,
            detail=(
                f"Rate limit exceeded: {config.RATE_LIMIT_REQUESTS} requests "
                f"per {config.RATE_LIMIT_WINDOW_SECONDS}s."
            ),
        )
    log.append(now)


def check_daily_quota(client_id: str) -> int:
    today = int(time.time() // 86400)
    if _daily_quota_day[client_id] != today:
        _daily_quota_day[client_id] = today
        _daily_quota_log[client_id] = 0
    _daily_quota_log[client_id] += 1
    if _daily_quota_log[client_id] > config.DAILY_QUOTA:
        logger.info("daily_quota_exceeded", extra={"client_id": client_id})
        raise HTTPException(
            status_code=429,
            detail=f"Daily quota of {config.DAILY_QUOTA} requests exceeded for this client.",
        )
    return _daily_quota_log[client_id]


def reset_rate_limit_state() -> None:
    """Test helper: clear in-memory limiter state between test cases."""
    _request_log.clear()
    _daily_quota_log.clear()
    _daily_quota_day.clear()

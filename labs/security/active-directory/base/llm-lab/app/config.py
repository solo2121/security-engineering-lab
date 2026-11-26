"""
Configuration for the OWASP Top 10 for LLM Applications training lab.

Everything here is overridable via environment variables so the app behaves
the same way whether it's run directly (`uvicorn app.main:app`) or under the
systemd unit installed on the llm01 VM. Nothing in this file reaches out to
the network or any external service.
"""

from __future__ import annotations

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Lab identity
# ---------------------------------------------------------------------------
LAB_NAME = "OWASP Top 10 for LLM Applications — Training Lab"
LAB_TAXONOMY_VERSION = "OWASP Top 10 for LLM Applications 2025"
LAB_TAXONOMY_SOURCE = "https://genai.owasp.org/initiatives/top-10-for-llm-and-genai/"

# Run mode. "secure" (the default) mounts only the secure baseline API under
# /secure. "lab" also mounts the intentionally vulnerable scenario endpoints
# for training; the llm01 VM's systemd unit and the compose "lab" profile set
# it explicitly. Anything else is treated as "secure".
LAB_MODE = "lab" if os.environ.get("LLM_LAB_MODE", "secure").strip().lower() == "lab" else "secure"

# ---------------------------------------------------------------------------
# Filesystem layout — everything the app is allowed to touch lives under
# LAB_ROOT/data/sandbox. Nothing outside this tree is ever read or written
# as a result of user input.
# ---------------------------------------------------------------------------
LAB_ROOT = Path(os.environ.get("LLM_LAB_ROOT", Path(__file__).resolve().parents[1]))
DATA_DIR = LAB_ROOT / "data"
DOCUMENTS_DIR = DATA_DIR / "documents"
FAKE_SECRETS_DIR = DATA_DIR / "fake_secrets"
SANDBOX_DIR = DATA_DIR / "sandbox"

SANDBOX_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Safety constraints (see app/safety.py for enforcement)
# ---------------------------------------------------------------------------
# Fixed allowlist of "commands" the excessive-agency / prompt-injection
# scenarios are permitted to simulate. Nothing outside this list can ever be
# run, and even these are not passed to a real shell — see safety.py.
ALLOWED_COMMANDS = frozenset({"id", "whoami", "pwd", "uname", "echo"})

# Maximum size, in bytes, of any request body the app will parse.
MAX_REQUEST_BYTES = int(os.environ.get("LLM_LAB_MAX_REQUEST_BYTES", 8_192))

# Maximum length of any free-text field (prompt, query, document content).
MAX_TEXT_LENGTH = int(os.environ.get("LLM_LAB_MAX_TEXT_LENGTH", 4_000))

# Maximum size of any simulated "generated" output, to keep LLM10 demos
# bounded rather than actually exhausting memory.
MAX_OUTPUT_LENGTH = int(os.environ.get("LLM_LAB_MAX_OUTPUT_LENGTH", 20_000))

# Simple in-memory rate limit: N requests per WINDOW_SECONDS per client IP.
RATE_LIMIT_REQUESTS = int(os.environ.get("LLM_LAB_RATE_LIMIT_REQUESTS", 30))
RATE_LIMIT_WINDOW_SECONDS = int(os.environ.get("LLM_LAB_RATE_LIMIT_WINDOW", 60))

# Per-user (per API key header) daily quota, for the LLM10 scenario.
DAILY_QUOTA = int(os.environ.get("LLM_LAB_DAILY_QUOTA", 200))

# Synthetic-only marker prefixes. Anything returned by the app that looks
# like a secret is guaranteed to start with one of these so it can never be
# mistaken for a real credential.
SYNTHETIC_MARKER_PREFIXES = ("FAKE-ONLY-", "LAB_SECRET_", "SYNTHETIC-")

HOST = os.environ.get("LLM_LAB_HOST", "0.0.0.0")
PORT = int(os.environ.get("LLM_LAB_PORT", 8000))

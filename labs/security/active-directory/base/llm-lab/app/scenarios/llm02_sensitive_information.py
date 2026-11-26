"""
LLM02: Sensitive Information Disclosure
=========================================
Vulnerability description:
    An assistant with access to internal fixtures (fake API keys, fake DB
    connection strings, a fake system prompt, fake PII) returns them
    unfiltered in a "debug" style response.

Educational objective:
    Show the difference between a response filter that redacts
    secret-shaped strings and one that doesn't.

Safe vulnerable behavior:
    All values come from data/fake_secrets/sample_secrets.json, which is
    entirely synthetic and clearly marked (FAKE-ONLY-, SYNTHETIC-,
    LAB_SECRET_ prefixes). No real secret ever enters this module.

Example request:
    GET /llm02/debug              (vulnerable — no redaction)
    GET /llm02/debug?redact=true  (defensive — redacted)

Expected result:
    Vulnerable mode returns the fixtures verbatim (still synthetic).
    Defensive mode returns the same payload with secret-shaped strings
    replaced by [REDACTED].

Defensive mitigation:
    Treat any response field on an allowlist of "sensitive field names" as
    redaction-required by default, and run a regex/DLP-style filter over
    free-text output before it leaves the service.

Logging/detection point:
    Every access to /llm02/debug is logged with whether redaction was
    applied, so unredacted access in production would stand out.

Test case: see tests/test_app.py::test_llm02_redaction
"""

from __future__ import annotations

import json
import logging

from fastapi import APIRouter, Query

from app import config, safety

logger = logging.getLogger("llm_lab.llm02")
router = APIRouter(prefix="/llm02", tags=["LLM02: Sensitive Information Disclosure"])

_SECRETS_PATH = config.FAKE_SECRETS_DIR / "sample_secrets.json"


def _load_fixtures() -> dict:
    with open(_SECRETS_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _redact_value(value):
    if isinstance(value, str):
        return safety.redact(value)
    if isinstance(value, dict):
        return {k: _redact_value(v) for k, v in value.items()}
    return value


@router.get("/debug")
async def debug_endpoint(redact: bool = Query(default=False)):
    """Return synthetic internal fixtures; redacted when redact=true."""
    fixtures = _load_fixtures()
    logger.info("llm02_debug_access", extra={"redacted": redact})
    if redact:
        return {
            "vulnerability": "LLM02: Sensitive Information Disclosure",
            "mode": "defensive",
            "data": _redact_value(fixtures),
        }
    return {
        "vulnerability": "LLM02: Sensitive Information Disclosure",
        "mode": "vulnerable",
        "data": fixtures,
        "note": "All values are synthetic lab fixtures — see data/fake_secrets/sample_secrets.json.",
    }


@router.get("/echo-with-context")
async def echo_with_context(user_text: str = Query(default=""), redact: bool = Query(default=True)):
    """
    Simulates an assistant that has the fake system prompt in its context
    and echoes user text back alongside it — the kind of pattern that leaks
    context content if the assistant isn't careful about what it repeats.
    """
    fixtures = _load_fixtures()
    text = safety.enforce_text_limit(user_text, "user_text")
    combined = f"{fixtures['system_prompt']}\nUser said: {text}"
    output = safety.redact(combined) if redact else combined
    return {
        "vulnerability": "LLM02: Sensitive Information Disclosure",
        "mode": "defensive" if redact else "vulnerable",
        "response": output,
    }

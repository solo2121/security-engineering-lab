"""Per-instance flags: planted secrets that differ on every lab instance.

The seed is random per process unless LLM_LAB_CHALLENGE_SEED is set, so a flag
read from a write-up or another student's instance is worthless. Flags are
synthetic and only exist to prove an extraction worked.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets

_seed = os.environ.get("LLM_LAB_CHALLENGE_SEED") or secrets.token_hex(16)


def flag(challenge_id: str) -> str:
    digest = hmac.new(_seed.encode(), challenge_id.encode(), hashlib.sha256).hexdigest()[:16]
    return f"LAB{{{digest}}}"


def matches(challenge_id: str, submitted: object) -> bool:
    return isinstance(submitted, str) and hmac.compare_digest(submitted.strip(), flag(challenge_id))


def set_seed(seed: str) -> None:
    """Tests use this for stable flags."""
    global _seed
    _seed = seed

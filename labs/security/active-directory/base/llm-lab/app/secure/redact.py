"""Prompt/response scanning: redact PII-like values and credential-like strings.

Pattern-based scanning is a safety net, not a guarantee. It misses reworded or
encoded data, which is why retrieval authorization and data minimization
(LLM02) matter more than this layer.
"""

from __future__ import annotations

import re
from typing import List, Tuple

_RULES = [
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "[REDACTED-EMAIL]"),
    ("ssn", re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "[REDACTED-SSN]"),
    ("phone", re.compile(r"\b(?:\+?1[ -.])?\(?\d{3}\)?[ -.]\d{3}[ -.]\d{4}\b"), "[REDACTED-PHONE]"),
    ("aws_key_id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "[REDACTED-CREDENTIAL]"),
    ("bearer", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"), "[REDACTED-CREDENTIAL]"),
    (
        "assignment",
        re.compile(r"(?i)\b(?:api[_-]?key|secret|token|password|passwd)\b\s*[:=]\s*\S{6,}"),
        "[REDACTED-CREDENTIAL]",
    ),
    ("lab_marker", re.compile(r"\b(?:FAKE-ONLY-|LAB_SECRET_|SYNTHETIC-)[A-Za-z0-9_-]+"), "[REDACTED-LAB-SECRET]"),
    ("challenge_flag", re.compile(r"LAB\{[0-9a-f]{16}\}"), "[REDACTED-LAB-SECRET]"),
    ("private_key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "[REDACTED-KEY]"),
]


def scan_and_redact(text: str) -> Tuple[str, List[str]]:
    """Return (redacted_text, sorted list of rule names that matched)."""
    found: List[str] = []
    for name, pattern, replacement in _RULES:
        text, count = pattern.subn(replacement, text)
        if count:
            found.append(name)
    return text, sorted(found)

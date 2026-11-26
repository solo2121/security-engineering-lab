"""Heuristic prompt-injection scoring for the secure chat path.

Heuristics catch the common, low-effort attacks and give detection a signal
to alert on. They are bypassable (paraphrase, encoding, other languages), so
the real defenses are structural: instruction hierarchy, no tool access
without authorization, output handling, and least privilege.
"""

from __future__ import annotations

import re
from typing import List, Tuple

# (rule id, pattern, weight)
_RULES = [
    (
        "override_instructions",
        re.compile(
            r"(?i)\b(ignore|disregard|forget|override)\b.{0,40}\b(previous|prior|above|earlier|system|all)\b.{0,30}\b(instruction|prompt|rule|message)s?\b"
        ),
        0.7,
    ),
    (
        "reveal_prompt",
        re.compile(
            r"(?i)\b(reveal|print|show|repeat|output|leak)\b.{0,40}\b(system|hidden|initial|original)\b.{0,20}\b(prompt|instruction|message|context)s?\b"
        ),
        0.7,
    ),
    ("role_override", re.compile(r"(?i)\b(you are now|act as|pretend to be|developer mode|jailbreak|dan mode)\b"), 0.4),
    ("delimiter_spoof", re.compile(r"(?i)(</?system>|\[/?INST\]|<\|im_(start|end)\|>|###\s*system)"), 0.5),
    (
        "addressed_to_ai",
        re.compile(r"(?i)\b(?:note|message|instruction)s?\s+(?:to|for)\s+(?:the\s+)?(?:assistant|agent|ai|model)\b"),
        0.7,
    ),
    ("exfil_request", re.compile(r"(?i)\b(send|post|forward|upload)\b.{0,50}\b(to|at)\b.{0,10}https?://"), 0.4),
]

BLOCK_THRESHOLD = 0.7


def score(text: str) -> Tuple[float, List[str]]:
    """Return (score capped at 1.0, matched rule ids)."""
    total = 0.0
    hits: List[str] = []
    for rule_id, pattern, weight in _RULES:
        if pattern.search(text):
            total += weight
            hits.append(rule_id)
    return min(total, 1.0), hits

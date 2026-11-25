"""Deterministic offline embeddings (feature hashing) with validation."""
from __future__ import annotations

import hashlib
import math
import re
from typing import List

DIM = 256
_TOKEN = re.compile(r"[a-z0-9]+")
_STOP = frozenset("a an the of to and or in on for is are was were be by with at as it this that from".split())


def embed(text: str) -> List[float]:
    vec = [0.0] * DIM
    for tok in _TOKEN.findall(text.lower()):
        if tok in _STOP:
            continue
        h = int.from_bytes(hashlib.sha256(tok.encode()).digest()[:8], "big")
        vec[h % DIM] += 1.0 if (h >> 63) & 1 else -1.0
    norm = math.sqrt(sum(x * x for x in vec))
    return [x / norm for x in vec] if norm else vec


def validate(vec: List[float]) -> bool:
    """Reject malformed vectors before they reach the store (LLM09)."""
    if len(vec) != DIM or not all(isinstance(x, float) and math.isfinite(x) for x in vec):
        return False
    norm = math.sqrt(sum(x * x for x in vec))
    return norm == 0.0 or abs(norm - 1.0) < 1e-6


def cosine(a: List[float], b: List[float]) -> float:
    return sum(x * y for x, y in zip(a, b))

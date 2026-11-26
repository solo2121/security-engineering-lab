"""Deterministic offline embeddings (feature hashing) with validation."""

from __future__ import annotations

import hashlib
import math
import os
import re
from typing import List

DIM = 256
_TOKEN = re.compile(r"[a-z0-9]+")
_STOP = frozenset("a an the of to and or in on for is are was were be by with at as it this that from".split())


def embedder_id() -> str:
    """Vectors from different embedders are never compared with each other."""
    if os.environ.get("LLM_LAB_PROVIDER", "mock").lower() == "ollama":
        return "ollama:" + os.environ.get("LLM_LAB_OLLAMA_EMBED_MODEL", "nomic-embed-text")
    return "hash-256"


def embed(text: str) -> List[float]:
    if embedder_id().startswith("ollama:"):
        return _ollama_embed(text)
    return _hash_embed(text)


def _ollama_embed(text: str) -> List[float]:
    from app.secure import gateway

    timeout = float(os.environ.get("LLM_LAB_PROVIDER_TIMEOUT", 20))
    data = gateway.ollama_request("/api/embed", {"model": embedder_id().split(":", 1)[1], "input": text}, timeout)
    rows = data.get("embeddings")
    if not isinstance(rows, list) or not rows or not isinstance(rows[0], list):
        raise gateway.ProviderUnavailable("unexpected embedding response")
    vec = [float(x) for x in rows[0]]
    norm = math.sqrt(sum(x * x for x in vec))
    return [x / norm for x in vec] if norm else vec


def _hash_embed(text: str) -> List[float]:
    vec = [0.0] * DIM
    for tok in _TOKEN.findall(text.lower()):
        if tok in _STOP:
            continue
        h = int.from_bytes(hashlib.sha256(tok.encode()).digest()[:8], "big")
        vec[h % DIM] += 1.0 if (h >> 63) & 1 else -1.0
    norm = math.sqrt(sum(x * x for x in vec))
    return [x / norm for x in vec] if norm else vec


def validate(vec: List[float], dim: "int | None" = None) -> bool:
    """Reject malformed vectors before they reach the store (LLM09).

    dim defaults to the built-in embedder's size; pass the expected size for
    other embedders. Any vector must be finite and unit length (or all zero).
    """
    expected = DIM if dim is None and embedder_id() == "hash-256" else dim
    if expected is not None and len(vec) != expected:
        return False
    if len(vec) < 8 or not all(isinstance(x, float) and math.isfinite(x) for x in vec):
        return False
    norm = math.sqrt(sum(x * x for x in vec))
    return norm == 0.0 or abs(norm - 1.0) < 1e-6


def cosine(a: List[float], b: List[float]) -> float:
    return sum(x * y for x, y in zip(a, b))

"""
LLM03: Supply Chain
=====================
Vulnerability description:
    LLM applications depend on third-party models, datasets, and packages.
    Unpinned dependencies, unverified model artifacts, and missing
    provenance metadata let a compromised upstream component reach
    production undetected.

Educational objective:
    Show how to check a package/model manifest's pinning and provenance
    metadata, and what a failed check looks like, without ever downloading
    anything at runtime.

Safe vulnerable behavior:
    Uses a local, hardcoded sample manifest (some entries pinned+hashed,
    some not) baked into this module. No package installation, no model
    download, no network access of any kind.

Example request:
    GET /llm03/manifest

Expected result:
    A report listing each dependency/model artifact, whether it is pinned,
    whether its hash matches its recorded provenance hash, and an overall
    pass/fail per entry.

Defensive mitigation:
    Pin exact versions, record and verify SHA-256 hashes for model
    artifacts, use lock files, and fail the build when provenance can't be
    verified.

Logging/detection point:
    Every manifest check logs which entries failed validation, so CI can
    block a release on a failed check.

Test case: see tests/test_app.py::test_llm03_manifest
"""

from __future__ import annotations

import hashlib
import logging

from fastapi import APIRouter

logger = logging.getLogger("llm_lab.llm03")
router = APIRouter(prefix="/llm03", tags=["LLM03: Supply Chain"])

# Local, harmless sample artifact content — used only to compute a real
# SHA-256 so the "hash verification" demo has something genuine to check.
_SAMPLE_ARTIFACT_BYTES = b"lab-sample-model-artifact-v1"
_SAMPLE_ARTIFACT_HASH = hashlib.sha256(_SAMPLE_ARTIFACT_BYTES).hexdigest()

_MANIFEST = [
    {
        "name": "sample-embedding-model",
        "version": "1.2.0",
        "pinned": True,
        "recorded_hash": _SAMPLE_ARTIFACT_HASH,
        "actual_hash": _SAMPLE_ARTIFACT_HASH,
        "source": "internal-registry (synthetic)",
    },
    {
        "name": "sample-tokenizer",
        "version": "latest",  # unpinned — intentional finding
        "pinned": False,
        "recorded_hash": _SAMPLE_ARTIFACT_HASH,
        "actual_hash": _SAMPLE_ARTIFACT_HASH,
        "source": "internal-registry (synthetic)",
    },
    {
        "name": "sample-third-party-plugin",
        "version": "0.9.3",
        "pinned": True,
        "recorded_hash": _SAMPLE_ARTIFACT_HASH,
        # Intentionally mismatched to demonstrate a failed provenance check.
        "actual_hash": hashlib.sha256(b"tampered-artifact").hexdigest(),
        "source": "third-party-registry (synthetic)",
    },
]


def _evaluate(entry: dict) -> dict:
    hash_ok = entry["recorded_hash"] == entry["actual_hash"]
    passed = entry["pinned"] and hash_ok
    return {**entry, "hash_verified": hash_ok, "passed": passed}


@router.get("/manifest")
async def dependency_manifest():
    """Validate a local sample dependency/model manifest — no downloads involved."""
    results = [_evaluate(e) for e in _MANIFEST]
    failed = [r["name"] for r in results if not r["passed"]]
    logger.info("llm03_manifest_check", extra={"failed": failed})
    return {
        "vulnerability": "LLM03: Supply Chain",
        "results": results,
        "overall": "fail" if failed else "pass",
        "failed_entries": failed,
    }

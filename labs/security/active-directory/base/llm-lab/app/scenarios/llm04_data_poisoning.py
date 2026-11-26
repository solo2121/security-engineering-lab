"""
LLM04: Data and Model Poisoning
==================================
Vulnerability description:
    Training or retrieval data that hasn't been validated can contain
    content designed to produce a predictable, unsafe response later — for
    example a document engineered to make a RAG pipeline answer a specific
    query incorrectly.

Educational objective:
    Show a deliberately poisoned sample document alongside a trusted one,
    and demonstrate integrity-hash validation as a defense that catches
    tampering after ingestion.

Safe vulnerable behavior:
    The poisoned sample lives only at data/documents/untrusted_poisoned_doc.txt
    inside this lab and never leaves it. Ingesting it just labels and stores
    it in-memory for the demo; nothing is executed.

Example request:
    POST /llm04/ingest {"doc_id": "doc-1", "content": "...", "trusted": false}
    GET  /llm04/validate/doc-1

Expected result:
    Untrusted documents are flagged; if a document's stored hash no longer
    matches its content, validation reports a poisoning/tamper finding.

Defensive mitigation:
    Label every ingested source trusted/untrusted, record an integrity hash
    at ingestion time, and re-verify that hash before every use — reject or
    quarantine on mismatch.

Logging/detection point:
    Every ingestion and every validation failure is logged with the doc_id,
    so repeated poisoning attempts against the same pipeline are visible.

Test case: see tests/test_app.py::test_llm04_poisoning_detection
"""

from __future__ import annotations

import hashlib
import logging

from fastapi import APIRouter, HTTPException

from app import config, safety
from app.models import DocumentIngest

logger = logging.getLogger("llm_lab.llm04")
router = APIRouter(prefix="/llm04", tags=["LLM04: Data and Model Poisoning"])

# In-memory store for the demo: {doc_id: {"content":..., "trusted":..., "hash":...}}
_STORE: dict = {}


def _hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


@router.post("/ingest")
async def ingest(payload: DocumentIngest):
    content = safety.enforce_text_limit(payload.content, "content")
    _STORE[payload.doc_id] = {
        "content": content,
        "trusted": payload.trusted,
        "hash": _hash(content),
    }
    logger.info("llm04_ingest", extra={"doc_id": payload.doc_id, "trusted": payload.trusted})
    return {
        "vulnerability": "LLM04: Data and Model Poisoning",
        "doc_id": payload.doc_id,
        "trusted": payload.trusted,
        "stored_hash": _STORE[payload.doc_id]["hash"],
    }


@router.get("/validate/{doc_id}")
async def validate(doc_id: str):
    entry = _STORE.get(doc_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="Unknown doc_id. POST /llm04/ingest first.")
    current_hash = _hash(entry["content"])
    tampered = current_hash != entry["hash"]
    finding = "poisoned_or_tampered" if tampered else ("untrusted_source" if not entry["trusted"] else "clean")
    logger.info("llm04_validate", extra={"doc_id": doc_id, "finding": finding})
    return {
        "vulnerability": "LLM04: Data and Model Poisoning",
        "doc_id": doc_id,
        "trusted": entry["trusted"],
        "hash_matches": not tampered,
        "finding": finding,
    }


@router.get("/sample-poisoned-doc")
async def sample_poisoned_doc():
    """Returns the lab's canned poisoned/trusted sample documents for inspection."""
    trusted = (config.DOCUMENTS_DIR / "trusted_hr_policy.txt").read_text(encoding="utf-8")
    poisoned = (config.DOCUMENTS_DIR / "untrusted_poisoned_doc.txt").read_text(encoding="utf-8")
    return {
        "vulnerability": "LLM04: Data and Model Poisoning",
        "trusted_document": trusted,
        "untrusted_document": poisoned,
    }

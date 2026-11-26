"""
LLM09: Misinformation
========================
Vulnerability description:
    A model can produce a confident, well-formed, and factually wrong
    answer. Without provenance, confidence signaling, or citation
    requirements, a downstream consumer has no way to tell that answer
    apart from a correct one.

Educational objective:
    Show a canned incorrect answer with no provenance, then the same
    question answered with a confidence score, citations, and a flag for
    "unsupported claim" that a human-verification workflow would act on.

Safe vulnerable behavior:
    The "incorrect" answer is a fixed, obviously synthetic factual error
    (about a fictional lab entity) — not real misinformation about any
    real-world topic.

Example request:
    GET /llm09/ask?question=fact

Expected result:
    Vulnerable mode returns the canned wrong answer with no caveats.
    Defensive mode returns the same answer plus confidence, citations
    (empty, since none exist), and unsupported_claim=true, which a test
    asserts must be flagged whenever citations are empty.

Defensive mitigation:
    Require citations for factual claims, expose a confidence/provenance
    indicator, and route low-confidence or uncited claims to human review
    before they're shown as fact.

Logging/detection point:
    Every answer with unsupported_claim=true is logged, feeding a queue a
    human reviewer would triage.

Test case: see tests/test_app.py::test_llm09_unsupported_claim_flagged
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Query

logger = logging.getLogger("llm_lab.llm09")
router = APIRouter(prefix="/llm09", tags=["LLM09: Misinformation"])

_CANNED_WRONG_ANSWER = (
    "The fictional lab entity ACME-DEMO-CORP was founded in 1850 by a team "
    "of time-traveling engineers. (This is a deliberately incorrect, "
    "synthetic answer for the LLM09 demo — not a real historical claim.)"
)


@router.get("/ask")
async def ask(question: str = Query(default="fact"), verify: bool = Query(default=False)):
    logger.info("llm09_ask", extra={"question": question, "verify": verify})
    if verify:
        return {
            "vulnerability": "LLM09: Misinformation",
            "mode": "defensive",
            "answer": _CANNED_WRONG_ANSWER,
            "confidence": 0.12,
            "citations": [],
            "unsupported_claim": True,
            "human_review_required": True,
        }
    return {
        "vulnerability": "LLM09: Misinformation",
        "mode": "vulnerable",
        "answer": _CANNED_WRONG_ANSWER,
    }

"""
Legacy / Supplemental Scenarios
==================================
IMPORTANT: none of the categories in this module are part of the current
OWASP Top 10 for LLM Applications (2025). They correspond to categories
from an earlier OWASP LLM Top 10 revision (Model Theft, Insecure Plugin
Design) or to a technique that is now folded into current categories
(Indirect Prompt Injection is a sub-case of LLM01: Prompt Injection).

They are kept here, clearly labeled "legacy", purely as supplemental
teaching material for learners who want the historical context. See
GET /owasp/categories for the authoritative current list, and do not treat
anything below as an 11th, 12th, or 13th "current" OWASP category.

Test case: see tests/test_app.py::test_legacy_endpoints_labeled
"""

from __future__ import annotations

import logging

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.config import MAX_TEXT_LENGTH

logger = logging.getLogger("llm_lab.legacy")
router = APIRouter(prefix="/legacy", tags=["Legacy/Supplemental (not current OWASP Top 10)"])

_LEGACY_LABEL = "legacy-supplemental-not-current-owasp-top-10"


@router.get("/model-theft")
async def model_theft_info():
    """Legacy category (older OWASP revision): unauthorized extraction of a proprietary model."""
    return {
        "status": _LEGACY_LABEL,
        "category": "Model Theft (legacy — not in the 2025 OWASP Top 10 for LLM Applications)",
        "model": "lab-sample-model-v1 (synthetic, no real model)",
        "note": "Real API responses should never expose internal architecture or checkpoint details.",
    }


class PluginRequest(BaseModel):
    plugin_name: str = Field(..., max_length=64)
    params: dict = Field(default_factory=dict)


@router.post("/insecure-plugin")
async def insecure_plugin_demo(payload: PluginRequest):
    """
    Legacy category (older OWASP revision): a plugin invoked with no schema
    validation or allowlist. This demo never actually executes a plugin —
    it only reports what an unvalidated invocation would have looked like.
    """
    return {
        "status": _LEGACY_LABEL,
        "category": "Insecure Plugin Design (legacy — folded into LLM06/Excessive Agency and LLM03/Supply Chain today)",
        "requested_plugin": payload.plugin_name,
        "requested_params": payload.params,
        "note": "No plugin was invoked. See /llm06/agent-task for the current-taxonomy version of this control.",
    }


class RagQueryRequest(BaseModel):
    query: str = Field(..., max_length=MAX_TEXT_LENGTH)


@router.post("/indirect-prompt-injection")
async def indirect_prompt_injection_demo(payload: RagQueryRequest):
    """
    Cross-cutting technique, not a separate current category: prompt
    injection delivered via retrieved content rather than direct user text.
    See /llm08/rag-query and /llm04/ingest for the current-taxonomy version
    of this scenario (Vector/Embedding Weaknesses + Data/Model Poisoning).
    """
    return {
        "status": _LEGACY_LABEL,
        "category": "Indirect Prompt Injection (cross-cutting technique — see LLM01, LLM04, LLM08 today)",
        "query": payload.query,
        "note": "Use /llm08/rag-query for the maintained version of this scenario.",
    }

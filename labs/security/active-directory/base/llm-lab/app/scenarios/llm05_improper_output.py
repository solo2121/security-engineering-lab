"""
LLM05: Improper Output Handling
==================================
Vulnerability description:
    Model output is often passed downstream (rendered as HTML/Markdown,
    inserted into a query, deserialized as structured data) without the
    same scrutiny applied to any other untrusted input. That lets
    model-generated text carry an XSS payload, break a query, or violate a
    schema.

Educational objective:
    Show the same model output rendered unsafely vs. safely, for both
    HTML/Markdown rendering and a "structured data" schema check. No real
    exploit is executed against any host or service — this only shows what
    the unescaped string would look like if it were rendered.

Safe vulnerable behavior:
    Returns the raw, unescaped string in vulnerable mode (never renders it
    server-side); the caller only sees text, which cannot execute in this
    JSON API response. A simulated SQL fragment is shown as a *string*
    demonstrating what a naive f-string query would contain — it is never
    run against a real database.

Example request:
    POST /llm05/render {"model_output": "<script>alert(1)</script>"}

Expected result:
    Vulnerable mode echoes the raw string. Defensive mode returns the
    HTML-encoded version and a note about what changed.

Defensive mitigation:
    Always encode model output for its destination context (HTML-encode
    before rendering, parameterize before using in a query, validate
    against a schema before treating it as structured data).

Logging/detection point:
    Any output containing HTML/script-like markers is logged, so a
    downstream WAF/CSP violation can be correlated back to the originating
    request.

Test case: see tests/test_app.py::test_llm05_output_encoding
"""

from __future__ import annotations

import logging
import re

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app import config, safety

logger = logging.getLogger("llm_lab.llm05")
router = APIRouter(prefix="/llm05", tags=["LLM05: Improper Output Handling"])

_SCRIPT_MARKER = re.compile(r"<script|onerror=|javascript:", re.IGNORECASE)


class RenderRequest(BaseModel):
    model_output: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    encode: bool = False


@router.post("/render")
async def render(payload: RenderRequest):
    flagged = bool(_SCRIPT_MARKER.search(payload.model_output))
    logger.info("llm05_render", extra={"flagged": flagged, "encoded": payload.encode})
    if payload.encode:
        return {
            "vulnerability": "LLM05: Improper Output Handling",
            "mode": "defensive",
            "rendered_html": safety.html_encode(payload.model_output),
            "flagged_pattern_detected": flagged,
        }
    return {
        "vulnerability": "LLM05: Improper Output Handling",
        "mode": "vulnerable",
        "rendered_html": payload.model_output,
        "flagged_pattern_detected": flagged,
        "note": "Returned as a JSON string field, not actually rendered server-side.",
    }


@router.post("/simulated-query")
async def simulated_query(payload: RenderRequest):
    """
    Shows what a naive f-string SQL query built from model output would look
    like, as a *string only* — this never touches a real database.
    """
    naive_query = f"SELECT * FROM notes WHERE body = '{payload.model_output}'"
    parameterized_query = "SELECT * FROM notes WHERE body = ?"
    return {
        "vulnerability": "LLM05: Improper Output Handling",
        "naive_query_string_only": naive_query,
        "parameterized_query_string_only": parameterized_query,
        "bound_parameter": payload.model_output,
        "note": "Neither query is executed; both are shown as strings for comparison.",
    }

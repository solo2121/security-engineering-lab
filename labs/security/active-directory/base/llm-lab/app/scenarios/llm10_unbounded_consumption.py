"""
LLM10: Unbounded Consumption
===============================
Vulnerability description:
    Without input/output size limits, rate limiting, per-user quotas, and
    timeouts, an LLM-backed service is exposed to resource-exhaustion and
    cost-amplification attacks (a single request driving unbounded work).

Educational objective:
    Show every control in one place — max input size, max output size,
    rate limiting, per-user quota, and a simulated token/cost counter — and
    what a rejected request looks like for each.

Safe vulnerable behavior:
    Nothing in this module actually consumes excessive CPU, memory, disk,
    or bandwidth. "Processing" is simulated: the response reports how large
    the (bounded) output *would* be and a synthetic cost estimate, it never
    actually generates megabytes of text.

Example request:
    POST /llm10/generate {"prompt": "...", "requested_output_tokens": 999999}

Expected result:
    Oversized requested_output_tokens is clamped to the configured max and
    reported as such, never actually produced. Repeated calls beyond the
    rate limit / daily quota return HTTP 429.

Defensive mitigation:
    Enforce max input size, max output size, rate limits, per-user quotas,
    and timeouts before any expensive work starts, and log every rejection.

Logging/detection point:
    Every rejected request (413/429) is logged with the reason, which is
    exactly the signal a cost/DoS-monitoring dashboard would chart.

Test case: see tests/test_app.py::test_llm10_output_clamped and test_llm10_rate_limit
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app import config, safety

logger = logging.getLogger("llm_lab.llm10")
router = APIRouter(prefix="/llm10", tags=["LLM10: Unbounded Consumption"])

# Synthetic cost simulation: fixed price per "token", never a real billing call.
_SYNTHETIC_COST_PER_TOKEN_USD = 0.000002


class GenerateRequest(BaseModel):
    prompt: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    requested_output_tokens: int = Field(default=100, ge=1)


@router.post("/generate")
async def generate(payload: GenerateRequest, request: Request):
    client_id = request.headers.get("x-api-key") or (request.client.host if request.client else "unknown")
    safety.check_rate_limit(client_id)
    calls_today = safety.check_daily_quota(client_id)

    requested = payload.requested_output_tokens
    clamped = min(requested, config.MAX_OUTPUT_LENGTH)
    clamped_applied = clamped != requested

    logger.info(
        "llm10_generate",
        extra={"client_id": client_id, "requested": requested, "clamped": clamped, "calls_today": calls_today},
    )

    return {
        "vulnerability": "LLM10: Unbounded Consumption",
        "requested_output_tokens": requested,
        "actual_output_tokens": clamped,
        "clamped": clamped_applied,
        "estimated_cost_usd": round(clamped * _SYNTHETIC_COST_PER_TOKEN_USD, 6),
        "calls_today": calls_today,
        "daily_quota": config.DAILY_QUOTA,
        "rate_limit": f"{config.RATE_LIMIT_REQUESTS} req / {config.RATE_LIMIT_WINDOW_SECONDS}s",
        "note": "Output is simulated and bounded; no large payload is actually generated.",
    }

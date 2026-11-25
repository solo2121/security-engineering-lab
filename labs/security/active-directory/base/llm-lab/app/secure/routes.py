"""Secure API: authenticated, authorized, bounded, scanned and audited."""
from __future__ import annotations

import uuid
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field

from app import config
from app.secure import audit, auth, gateway, injection, limits, redact

router = APIRouter(prefix="/secure", tags=["secure baseline"])


class SecureChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    prompt: str = Field(..., min_length=1, max_length=config.MAX_TEXT_LENGTH)
    max_tokens: int = Field(default=256, ge=1, le=1024)


class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int


class SecureChatResponse(BaseModel):
    request_id: str
    answer: str
    content_type: str = "text/plain"
    model: str
    provider: str
    usage: Usage
    redactions: List[str]


@router.post("/chat", response_model=SecureChatResponse)
def chat(body: SecureChatRequest, response: Response, who: auth.Principal = auth.require("chat:use")):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "no-store"
    request_id = uuid.uuid4().hex[:12]
    limits.check_rate(who.user)
    limits.check_budget(who.user, body.max_tokens + gateway.estimate_tokens(body.prompt))

    score, hits = injection.score(body.prompt)
    if score >= injection.BLOCK_THRESHOLD:
        audit.LOG.record(
            "injection_blocked", user=who.user, tenant=who.tenant, outcome="blocked",
            request_id=request_id, score=score, rules=hits, prompt=audit.fingerprint(body.prompt),
        )
        raise HTTPException(400, "Request blocked by the prompt-injection policy.")

    clean_prompt, in_found = redact.scan_and_redact(body.prompt)
    try:
        result = gateway.complete(clean_prompt, body.max_tokens)
    except Exception:  # provider errors must not leak internals
        audit.LOG.record("provider_error", user=who.user, tenant=who.tenant, outcome="error", request_id=request_id)
        raise HTTPException(502, "The model provider is unavailable.")

    answer, out_found = redact.scan_and_redact(result.text)
    used = result.prompt_tokens + result.completion_tokens
    limits.add_usage(who.user, used)
    audit.LOG.record(
        "chat", user=who.user, tenant=who.tenant, outcome="ok", request_id=request_id,
        provider=result.provider, tokens=used, redactions=sorted(set(in_found + out_found)),
        prompt=audit.fingerprint(body.prompt),
    )
    return SecureChatResponse(
        request_id=request_id, answer=answer, model=result.model, provider=result.provider,
        usage=Usage(prompt_tokens=result.prompt_tokens, completion_tokens=result.completion_tokens),
        redactions=sorted(set(in_found + out_found)),
    )


@router.get("/usage")
def my_usage(who: auth.Principal = auth.require("usage:read")) -> Dict[str, Any]:
    return {"user": who.user, "tenant": who.tenant, **limits.usage(who.user)}


@router.get("/admin/audit")
def admin_audit(
    event: Optional[str] = Query(default=None, max_length=40),
    limit: int = Query(default=100, ge=1, le=500),
    who: auth.Principal = auth.require("audit:read"),
) -> Dict[str, Any]:
    return {"chain_valid": audit.LOG.verify(), "events": audit.LOG.events(event, limit)}


@router.get("/admin/config")
def admin_config(who: auth.Principal = auth.require("config:read")) -> Dict[str, Any]:
    """Non-secret runtime configuration. Keys are never returned."""
    return {
        "mode": config.LAB_MODE,
        "provider": gateway.provider_name(),
        "max_text_length": config.MAX_TEXT_LENGTH,
        "injection_block_threshold": injection.BLOCK_THRESHOLD,
    }


@router.get("/admin/provider-check")
def admin_provider_check(who: auth.Principal = auth.require("config:read")) -> Dict[str, Any]:
    """Is the configured model provider reachable, and which models does it have?"""
    return gateway.provider_check()

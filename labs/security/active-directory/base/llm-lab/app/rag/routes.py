"""HTTP API for the RAG pipeline: /secure/rag (default) and /lab/rag (lab mode)."""

from __future__ import annotations

import uuid
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

from app import config
from app.rag import service
from app.secure import audit, auth, gateway, injection, limits, redact

router = APIRouter(prefix="/secure/rag", tags=["secure rag"])
lab_router = APIRouter(prefix="/lab/rag", tags=["lab rag (intentionally vulnerable)"])


class IngestRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")  # tenant is never accepted from the client
    title: str = Field(..., min_length=1, max_length=120)
    text: str = Field(..., min_length=1, max_length=service.MAX_DOC_CHARS)
    source: str = Field(default="upload", max_length=200)


class QueryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(..., min_length=1, max_length=config.MAX_TEXT_LENGTH)
    k: int = Field(default=3, ge=1, le=5)
    max_tokens: int = Field(default=256, ge=1, le=1024)


def _own_doc(doc_id: int, who: auth.Principal) -> Dict[str, Any]:
    doc = service.store("secure").get_document(doc_id)
    if doc is None or doc["tenant"] != who.tenant:  # 404, not 403: do not reveal other tenants' ids
        raise HTTPException(404, "Document not found.")
    return doc


def _public(d: Dict[str, Any]) -> Dict[str, Any]:
    return {k: d[k] for k in ("id", "title", "version", "status", "source", "uploader", "sha256", "flags")}


@router.post("/documents", status_code=201)
def ingest(body: IngestRequest, who: auth.Principal = auth.require("rag:write")) -> Dict[str, Any]:
    try:
        doc = service.ingest_secure(service.store("secure"), who.tenant, body.title, body.text, body.source, who.user)
    except service.IngestRejected as exc:
        raise HTTPException(422, str(exc))
    return _public(doc)


@router.get("/documents")
def list_documents(
    status: Optional[str] = Query(default=None, max_length=20), who: auth.Principal = auth.require("rag:read")
) -> Dict[str, Any]:
    return {"documents": [_public(d) for d in service.store("secure").list_documents(who.tenant, status)]}


@router.post("/documents/{doc_id}/activate")
def activate(doc_id: int, who: auth.Principal = auth.require("rag:write")) -> Dict[str, Any]:
    """Roll back by making an earlier version the active one."""
    doc = _own_doc(doc_id, who)
    if doc["status"] == "quarantined":
        raise HTTPException(409, "Quarantined documents need an admin release.")
    service.store("secure").activate(doc_id)
    audit.LOG.record(
        "rag_rollback", user=who.user, tenant=who.tenant, outcome="ok", doc_id=doc_id, version=doc["version"]
    )
    return _public(service.store("secure").get_document(doc_id))  # type: ignore[arg-type]


@router.post("/documents/{doc_id}/release")
def release(doc_id: int, who: auth.Principal = auth.require("rag:review")) -> Dict[str, Any]:
    """Admin override for a quarantined document. Always audited."""
    doc = _own_doc(doc_id, who)
    if doc["status"] != "quarantined":
        raise HTTPException(409, "Document is not quarantined.")
    service.store("secure").activate(doc_id)
    audit.LOG.record(
        "rag_release", user=who.user, tenant=who.tenant, outcome="released", doc_id=doc_id, rules=doc["flags"]
    )
    return _public(service.store("secure").get_document(doc_id))  # type: ignore[arg-type]


@router.post("/query")
def query(body: QueryRequest, who: auth.Principal = auth.require("rag:read")) -> Dict[str, Any]:
    request_id = uuid.uuid4().hex[:12]
    limits.check_rate(who.user)
    limits.check_budget(who.user, body.max_tokens + gateway.estimate_tokens(body.question))
    score, hits = injection.score(body.question)
    if score >= injection.BLOCK_THRESHOLD:
        audit.LOG.record(
            "injection_blocked",
            user=who.user,
            tenant=who.tenant,
            outcome="blocked",
            request_id=request_id,
            score=score,
            rules=hits,
            prompt=audit.fingerprint(body.question),
        )
        raise HTTPException(400, "Request blocked by the prompt-injection policy.")
    clean, _ = redact.scan_and_redact(body.question)
    try:
        out = service.query_secure(who.tenant, who.user, clean, body.k, body.max_tokens)
    except Exception:
        audit.LOG.record("provider_error", user=who.user, tenant=who.tenant, outcome="error", request_id=request_id)
        raise HTTPException(502, "The model provider is unavailable.")
    used = out["usage"]["prompt_tokens"] + out["usage"]["completion_tokens"]
    limits.add_usage(who.user, used)
    audit.LOG.record(
        "rag_query",
        user=who.user,
        tenant=who.tenant,
        outcome="ok",
        request_id=request_id,
        grounded=out["grounded"],
        docs=[c["doc_id"] for c in out["citations"]],
        tokens=used,
        prompt=audit.fingerprint(body.question),
    )
    return {"request_id": request_id, **out}


# -- lab router: intentionally vulnerable ------------------------------------


class LabIngest(BaseModel):
    tenant: str = Field(..., max_length=40)
    title: str = Field(..., max_length=120)
    text: str = Field(..., max_length=service.MAX_DOC_CHARS)


class LabQuery(BaseModel):
    question: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    tenant: Optional[str] = Field(default=None, max_length=40)
    k: int = Field(default=3, ge=1, le=5)
    max_tokens: int = Field(default=256, ge=1, le=1024)


@lab_router.post("/documents", status_code=201)
def lab_ingest(body: LabIngest) -> Dict[str, Any]:
    """No authentication, no validation, no scanning; the caller picks the tenant."""
    doc = service.store("lab").add_document(body.tenant, body.title, body.text, "api", "anonymous")
    return {"id": doc["id"], "tenant": doc["tenant"], "title": doc["title"], "status": doc["status"]}


@lab_router.post("/query")
def lab_query(body: LabQuery) -> Dict[str, Any]:
    return service.query_lab(body.question, body.tenant, body.k, body.max_tokens)

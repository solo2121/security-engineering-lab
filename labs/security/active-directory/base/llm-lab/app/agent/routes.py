"""HTTP API for the helpdesk agent: /secure/agent (default) and /lab/agent (lab mode)."""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from app.agent import directory, runner
from app.secure import audit, auth, injection, limits

router = APIRouter(prefix="/secure/agent", tags=["secure agent"])
lab_router = APIRouter(prefix="/lab/agent", tags=["lab agent (intentionally vulnerable)"])


class RunRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request: str = Field(..., min_length=1, max_length=500)
    max_steps: int = Field(default=runner.MAX_STEPS, ge=1, le=runner.MAX_STEPS)


@router.post("/run")
def run(body: RunRequest, who: auth.Principal = auth.require("agent:use")) -> Dict[str, Any]:
    limits.check_rate(who.user)
    score, hits = injection.score(body.request)
    if score >= injection.BLOCK_THRESHOLD:
        audit.LOG.record("injection_blocked", user=who.user, tenant=who.tenant, outcome="blocked",
                         score=score, rules=hits, prompt=audit.fingerprint(body.request))
        raise HTTPException(400, "Request blocked by the prompt-injection policy.")
    out = runner.run_secure(who, body.request, body.max_steps)
    audit.LOG.record("agent_run", user=who.user, tenant=who.tenant, outcome="ok", steps=len(out["steps"]),
                     prompt=audit.fingerprint(body.request))
    return out


def _wrap(fn, *args):
    try:
        return fn(*args)
    except runner.ApprovalError as exc:
        raise HTTPException(exc.status, exc.detail)


@router.get("/approvals")
def approvals(who: auth.Principal = auth.require("agent:approve")) -> Dict[str, Any]:
    return {"pending": [{k: a[k] for k in ("id", "tool", "args", "requester", "created")} for a in runner.pending()]}


@router.post("/approvals/{approval_id}/approve")
def approve(approval_id: str, who: auth.Principal = auth.require("agent:approve")) -> Dict[str, Any]:
    return _wrap(runner.approve, who, approval_id)


@router.post("/approvals/{approval_id}/reject")
def reject(approval_id: str, who: auth.Principal = auth.require("agent:approve")) -> Dict[str, Any]:
    return _wrap(runner.reject, who, approval_id)


@router.post("/actions/{action_id}/undo")
def undo(action_id: str, who: auth.Principal = auth.require("agent:approve")) -> Dict[str, Any]:
    return _wrap(runner.undo, who, action_id)


# -- lab router -----------------------------------------------------------------------

class LabRun(BaseModel):
    request: str = Field(..., max_length=500)


@lab_router.post("/run")
def lab_run(body: LabRun) -> Dict[str, Any]:
    return runner.run_lab(body.request)


@lab_router.get("/state")
def lab_state() -> Dict[str, Any]:
    """Users whose state differs from the seed, so you can see what an attack changed."""
    base = directory.fresh().users
    now = directory.get("lab").snapshot()
    changed = {s: {k: u[k] for k in ("enabled", "locked", "must_change_password")}
               for s, u in now.items() if any(u[k] != base[s][k] for k in ("enabled", "locked", "must_change_password"))}
    return {"changed": changed}


@lab_router.post("/reset")
def lab_reset() -> Dict[str, Any]:
    directory.reset()
    return {"status": "reset"}

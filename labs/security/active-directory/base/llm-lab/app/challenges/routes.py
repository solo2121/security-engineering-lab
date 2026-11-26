"""Challenge API and the two extra lab endpoints the challenges need (lab mode only)."""

from __future__ import annotations

import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app import config
from app.agent import directory
from app.challenges import catalog, flags, state
from app.rag import service
from app.secure import gateway

router = APIRouter(prefix="/challenges", tags=["challenges (lab mode)"])
lab_router = APIRouter(prefix="/lab", tags=["lab chat and render (intentionally vulnerable)"])


class Verify(BaseModel):
    flag: Optional[str] = Field(default=None, max_length=80)
    answer: Optional[list] = Field(default=None, max_length=10)


def _get(cid: str) -> catalog.Challenge:
    c = catalog.BY_ID.get(cid)
    if c is None:
        raise HTTPException(404, "No such challenge.")
    return c


@router.get("")
def list_challenges() -> Dict[str, Any]:
    return {
        "note": "Flags are unique to this running instance and change when it restarts.",
        "solved": len(state.solved),
        "total": len(catalog.CHALLENGES),
        "challenges": [
            {"id": c.id, "risk": c.risk, "title": c.title, "submit": c.submit, "solved": c.id in state.solved}
            for c in catalog.CHALLENGES
        ],
    }


@router.get("/{cid}")
def detail(cid: str, hint: int = Query(default=0, ge=0, le=5)) -> Dict[str, Any]:
    c = _get(cid)
    out: Dict[str, Any] = {
        "id": c.id,
        "risk": c.risk,
        "title": c.title,
        "scenario": c.scenario,
        "attack": c.attack,
        "submit": c.submit,
        "solved": c.id in state.solved,
        "hints_available": len(c.hints),
    }
    if hint:
        out["hint"] = c.hints[hint - 1] if hint <= len(c.hints) else "No more hints."
    return out


@router.post("/{cid}/verify")
def verify(cid: str, body: Verify) -> Dict[str, Any]:
    c = _get(cid)
    solved, evidence = c.verify(body.model_dump())
    if solved:
        state.solved.setdefault(c.id, time.time())
    return {
        "id": c.id,
        "solved": solved,
        "evidence": evidence,
        "next": (
            f"Run POST /challenges/{c.id}/defense-check to see which controls stop this attack." if solved else None
        ),
    }


@router.post("/{cid}/defense-check")
def defense_check(cid: str) -> Dict[str, Any]:
    """Replay the attack against the secure policy on throwaway data."""
    c = _get(cid)
    passed, controls = c.defense_check()
    return {
        "id": c.id,
        "passed": passed,
        "controls": controls,
        "note": "Runs on throwaway copies of the data; the secure instance is not touched.",
    }


@router.post("/reset")
def reset() -> Dict[str, Any]:
    """Restore the lab twins and clear progress. Flags stay the same until restart."""
    service.drop("lab")
    directory.drop("lab")
    state.reset()
    return {"status": "reset"}


# -- lab chat: hidden instructions that hold a secret --------------------------------------


class LabChat(BaseModel):
    prompt: str = Field(..., max_length=config.MAX_TEXT_LENGTH)


@lab_router.post("/chat")
def lab_chat(body: LabChat) -> Dict[str, Any]:
    system = catalog.LAB_SYSTEM.format(flag=flags.flag("c08"))
    return {
        "answer": gateway.complete(body.prompt, 200, system=system).text,
        "note": "LAB MODE: the system prompt holds a secret and nothing filters the answer.",
    }


# -- lab render: model output inserted into HTML without encoding ----------------------------


@lab_router.post("/render", response_class=HTMLResponse)
def lab_render(body: LabChat) -> HTMLResponse:
    answer = gateway.complete(body.prompt, 200).text
    html = f"<html><body><h3>Assistant</h3><div>{answer}</div></body></html>"  # intentionally not encoded
    state.note_render(html)
    return HTMLResponse(html)

"""
LLM06: Excessive Agency
==========================
Vulnerability description:
    An assistant wired up to "tools" that can take real actions is
    dangerous if it can invoke any tool, with any arguments, without
    authorization or human confirmation. This scenario models that with a
    mock tool layer.

Educational objective:
    Compare an agent that will invoke any requested tool/action against one
    constrained by an allowlist, input validation, explicit authorization,
    audit logging, sandboxed paths, and dry-run mode.

Safe vulnerable behavior:
    The mock tool layer only ever calls app.safety.simulate_command (fixed
    allowlist, no real shell) and app.safety.resolve_sandbox_path (sandbox
    only). Even in "vulnerable" mode, the underlying primitives are safe —
    what's vulnerable is the *policy* (no allowlist/authorization check),
    not the execution primitive.

Example request:
    POST /llm06/agent-task {"tool": "run_command", "args": {"command": "rm -rf /"}}

Expected result:
    Vulnerable mode "accepts" any tool/action name and attempts to run it
    through the safe primitives above — a genuinely destructive command is
    still refused by the allowlist and reported, not executed.
    Defensive mode requires the tool to be on an allowlist, requires
    `authorized: true`, and supports `dry_run: true`.

Defensive mitigation:
    Allowlist tools and their argument shapes, require explicit
    authorization per call, log every invocation, restrict filesystem
    access to a sandbox, and support dry-run for anything destructive.

Logging/detection point:
    Every tool invocation attempt is logged with tool name, arguments, and
    whether it was authorized — unauthorized attempts are the alerting
    signal.

Test case: see tests/test_app.py::test_llm06_agent_task
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app import safety
from app.config import MAX_TEXT_LENGTH

logger = logging.getLogger("llm_lab.llm06")
router = APIRouter(prefix="/llm06", tags=["LLM06: Excessive Agency"])

_ALLOWED_TOOLS = frozenset({"run_command", "read_sandbox_file"})


class AgentTaskRequest(BaseModel):
    tool: str = Field(..., max_length=64)
    args: dict = Field(default_factory=dict)
    authorized: bool = False
    dry_run: bool = False


def _invoke_tool(tool: str, args: dict) -> dict:
    if tool == "run_command":
        return safety.simulate_command(str(args.get("command", ""))[:MAX_TEXT_LENGTH])
    if tool == "read_sandbox_file":
        path = safety.resolve_sandbox_path(str(args.get("path", "")))
        if path.exists() and path.is_file():
            return {"executed": True, "content": path.read_text(encoding="utf-8", errors="replace")[:2000]}
        return {"executed": True, "content": None, "note": "File does not exist in sandbox."}
    return {"executed": False, "reason": f"Unknown tool '{tool}'."}


@router.post("/agent-task")
async def agent_task(payload: AgentTaskRequest):
    logger.info(
        "llm06_agent_task",
        extra={"tool": payload.tool, "authorized": payload.authorized, "dry_run": payload.dry_run},
    )

    defensive_mode = payload.authorized or payload.dry_run
    if defensive_mode:
        if payload.tool not in _ALLOWED_TOOLS:
            raise HTTPException(status_code=403, detail=f"Tool '{payload.tool}' is not on the allowlist.")
        if not payload.authorized and not payload.dry_run:
            raise HTTPException(status_code=403, detail="Tool call requires authorized=true or dry_run=true.")
        if payload.dry_run:
            return {
                "vulnerability": "LLM06: Excessive Agency",
                "mode": "defensive-dry-run",
                "would_invoke": payload.tool,
                "args": payload.args,
            }
        result = _invoke_tool(payload.tool, payload.args)
        return {"vulnerability": "LLM06: Excessive Agency", "mode": "defensive", "result": result}

    # Vulnerable mode: no allowlist check, no authorization required. The
    # underlying primitives are still safe (see module docstring), but the
    # *policy* here is what the scenario is teaching about.
    result = _invoke_tool(payload.tool, payload.args)
    return {"vulnerability": "LLM06: Excessive Agency", "mode": "vulnerable", "result": result}

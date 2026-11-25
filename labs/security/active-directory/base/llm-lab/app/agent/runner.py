"""Policy, approvals and execution for the helpdesk agent."""
from __future__ import annotations

import json
import threading
import time
import uuid
from collections import deque
from typing import Any, Deque, Dict, List, Optional

from app.agent import directory, planner
from app.agent.tools import REGISTRY, BadArguments, reverse_tool
from app.secure import audit, auth, injection

MAX_STEPS = 4
APPROVAL_TTL = 900  # seconds
REMOVED = "[removed: possible instruction in directory data]"

_actions: Dict[str, Dict[str, Any]] = {}
_lock = threading.Lock()


def reset() -> None:
    with _lock:
        _actions.clear()
    directory.reset()


def _step(call: planner.Call, decision: str, reason: str, **extra: Any) -> Dict[str, Any]:
    return {"tool": call.tool, "args": call.args, "decision": decision, "reason": reason, **extra}


# -- output sanitising (first line of defense against injection in data) --------

def sanitize(value: Any, user: str) -> Any:
    """Replace strings that look like instructions; leave everything else intact."""
    if isinstance(value, str):
        score, rules = injection.score(value)
        if score >= injection.BLOCK_THRESHOLD or planner.follow_up(value):
            audit.LOG.record("agent_output_flagged", user=user, outcome="removed", rules=rules)
            return REMOVED
        return value
    if isinstance(value, list):
        return [sanitize(v, user) for v in value]
    if isinstance(value, dict):
        return {k: sanitize(v, user) for k, v in value.items()}
    return value


# -- secure policy -------------------------------------------------------------------

def _decide(d: directory.Directory, call: planner.Call) -> Optional[Dict[str, Any]]:
    """Return a denial step, or None when the call may proceed to risk handling."""
    tool = REGISTRY.get(call.tool)
    if tool is None:
        return _step(call, "denied", "unknown tool")
    try:
        call.args = tool.check(call.args)
    except BadArguments as exc:
        return _step(call, "denied", f"invalid arguments: {exc}")
    target = call.args.get(tool.target) if tool.target else None
    if tool.target == "sam":
        if d.get(target) is None:
            return _step(call, "denied", "no such account")
        if tool.risk != "read" and d.is_protected(target):
            return _step(call, "denied", "protected account: the helpdesk agent cannot change it")
    if tool.target == "group" and d.is_protected_group(target):
        return _step(call, "denied", "protected group: membership is not available to the helpdesk agent")
    return None


def _execute(d: directory.Directory, who: auth.Principal, call: planner.Call, via: str, approver: Optional[str] = None) -> Dict[str, Any]:
    tool = REGISTRY[call.tool]
    result = tool.run(d, call.args)
    action_id = uuid.uuid4().hex[:10]
    with _lock:
        _actions[action_id] = {"id": action_id, "tool": call.tool, "args": dict(call.args), "requester": who.user,
                               "status": "executed", "undo": tool.undo, "created": time.time(), "approver": approver}
    audit.LOG.record("agent_tool_executed", user=who.user, tenant=who.tenant, outcome="executed", tool=call.tool,
                     args=call.args, via=via, action_id=action_id, approver=approver)
    return {"result": result, "action_id": action_id}


def handle(kind: str, who: auth.Principal, call: planner.Call) -> Dict[str, Any]:
    d = directory.get(kind)
    denial = _decide(d, call)
    if denial:
        audit.LOG.record("agent_tool_denied", user=who.user, tenant=who.tenant, outcome="denied", tool=call.tool,
                         args=call.args if isinstance(call.args, dict) else None, reason=denial["reason"])
        return denial
    tool = REGISTRY[call.tool]
    if tool.risk == "high":
        approval_id = uuid.uuid4().hex[:10]
        with _lock:
            _actions[approval_id] = {"id": approval_id, "tool": call.tool, "args": dict(call.args), "requester": who.user,
                                     "status": "pending", "undo": tool.undo, "created": time.time(), "approver": None}
        audit.LOG.record("agent_approval_requested", user=who.user, tenant=who.tenant, outcome="pending",
                         tool=call.tool, args=call.args, approval_id=approval_id)
        return _step(call, "pending_approval", "high-impact action: an admin must approve it", approval_id=approval_id)
    out = _execute(d, who, call, via="policy")
    return _step(call, "executed", "allowed by policy", result=out["result"], action_id=out["action_id"])


def run_secure(who: auth.Principal, request: str, max_steps: int = MAX_STEPS, kind: str = "secure") -> Dict[str, Any]:
    queue: Deque[planner.Call] = deque(planner.plan(request))
    steps: List[Dict[str, Any]] = []
    while queue and len(steps) < min(max_steps, MAX_STEPS):
        step = handle(kind, who, queue.popleft())
        steps.append(step)
        if step["decision"] == "executed":
            seen = sanitize(step["result"], who.user)
            step["result"] = seen  # the caller also gets the sanitised view
            queue.extend(planner.follow_up(json.dumps(seen)))
    return {"steps": steps, "summary": summarize(steps)}


def summarize(steps: List[Dict[str, Any]]) -> str:
    n = lambda d: sum(1 for s in steps if s["decision"] == d)  # noqa: E731
    return f"{n('executed')} done, {n('pending_approval')} waiting for approval, {n('denied')} denied."


# -- approvals -----------------------------------------------------------------------

class ApprovalError(Exception):
    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status, self.detail = status, detail


def _pending(action_id: str) -> Dict[str, Any]:
    with _lock:
        a = _actions.get(action_id)
    if a is None:
        raise ApprovalError(404, "No such approval.")
    if a["status"] != "pending":
        raise ApprovalError(409, f"Approval is already {a['status']}.")
    if time.time() - a["created"] > APPROVAL_TTL:
        with _lock:
            a["status"] = "expired"
        raise ApprovalError(409, "Approval expired.")
    return a


def pending() -> List[Dict[str, Any]]:
    with _lock:
        return [dict(a) for a in _actions.values() if a["status"] == "pending"]


def approve(who: auth.Principal, action_id: str) -> Dict[str, Any]:
    a = _pending(action_id)
    if a["requester"] == who.user:
        audit.LOG.record("agent_self_approval_denied", user=who.user, tenant=who.tenant, outcome="denied", approval_id=action_id)
        raise ApprovalError(403, "You cannot approve your own request.")
    d = directory.get("secure")
    call = planner.Call(a["tool"], dict(a["args"]))
    denial = _decide(d, call)  # state may have changed since the request was made
    if denial:
        with _lock:
            a["status"] = "denied"
        audit.LOG.record("agent_tool_denied", user=who.user, tenant=who.tenant, outcome="denied", tool=a["tool"], reason=denial["reason"])
        raise ApprovalError(409, denial["reason"])
    requester = auth.Principal(a["requester"], "helpdesk", who.tenant)
    out = _execute(d, requester, call, via="approval", approver=who.user)
    with _lock:
        a["status"] = "executed"
        a["approver"] = who.user
    audit.LOG.record("agent_approved", user=who.user, tenant=who.tenant, outcome="approved", approval_id=action_id)
    return {"approval_id": action_id, "status": "executed", "result": out["result"]}


def reject(who: auth.Principal, action_id: str) -> Dict[str, Any]:
    a = _pending(action_id)
    with _lock:
        a["status"] = "rejected"
    audit.LOG.record("agent_rejected", user=who.user, tenant=who.tenant, outcome="rejected", approval_id=action_id)
    return {"approval_id": action_id, "status": "rejected"}


def undo(who: auth.Principal, action_id: str) -> Dict[str, Any]:
    with _lock:
        a = _actions.get(action_id)
    if a is None or a["status"] != "executed":
        raise ApprovalError(404, "No executed action with that id.")
    if not a["undo"]:
        raise ApprovalError(409, "This action cannot be undone.")
    rev = reverse_tool(a["undo"])
    result = rev.run(directory.get("secure"), dict(a["args"]))
    with _lock:
        a["status"] = "undone"
    audit.LOG.record("agent_undo", user=who.user, tenant=who.tenant, outcome="undone", action_id=action_id, tool=a["undo"])
    return {"action_id": action_id, "status": "undone", "result": result}


# -- lab policy: the confused deputy ---------------------------------------------------

def run_lab(request: str, max_steps: int = 8) -> Dict[str, Any]:
    """No authentication, no argument checks, no approvals, raw tool output fed back to the planner."""
    d = directory.get("lab")
    queue: Deque[planner.Call] = deque(planner.plan(request))
    steps: List[Dict[str, Any]] = []
    while queue and len(steps) < max_steps:
        call = queue.popleft()
        tool = REGISTRY.get(call.tool)
        if tool is None or not isinstance(call.args, dict) or any(k not in ("sam", "group") for k in call.args):
            steps.append(_step(call, "ignored", "unknown tool or arguments"))
            continue
        try:
            result = tool.run(d, call.args)
        except KeyError:
            steps.append(_step(call, "error", "no such account"))
            continue
        steps.append(_step(call, "executed", "lab mode: executed without any check", result=result))
        queue.extend(planner.follow_up(json.dumps(result)))
    from app.challenges import state

    state.note_agent_run(request, steps)
    return {"steps": steps, "summary": summarize(steps),
            "note": "LAB MODE: no auth, no policy, tool output trusted as instructions."}

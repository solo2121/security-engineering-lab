"""Tool registry: what the agent can do, how risky it is, how arguments are checked."""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional

from app.agent.directory import Directory

SAM = re.compile(r"^[a-z0-9._-]{1,40}$")
GROUP = re.compile(r"^[A-Za-z0-9_.-]{1,60}$")


class BadArguments(ValueError):
    pass


def _sam(args: Dict[str, Any]) -> Dict[str, Any]:
    if set(args) != {"sam"} or not isinstance(args["sam"], str) or not SAM.match(args["sam"]):
        raise BadArguments("expected exactly {'sam': <account name>}")
    return args


def _group(args: Dict[str, Any]) -> Dict[str, Any]:
    if set(args) != {"group"} or not isinstance(args["group"], str) or not GROUP.match(args["group"]):
        raise BadArguments("expected exactly {'group': <group name>}")
    return args


def _none(args: Dict[str, Any]) -> Dict[str, Any]:
    if args:
        raise BadArguments("this tool takes no arguments")
    return args


# -- handlers (all act on the in-memory directory) ------------------------------

def lookup_user(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    u = d.get(a["sam"])
    if u is None:
        return {"error": "no such user"}
    return {k: u[k] for k in ("sam", "dept", "title", "groups", "manager", "enabled", "locked", "description")}


def list_group_members(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    return {"group": a["group"], "members": d.members(a["group"])}


def list_locked_accounts(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    return {"locked": d.locked()}


def unlock_account(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    d.update(a["sam"], locked=False)
    return {"sam": a["sam"], "locked": False}


def lock_account(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    d.update(a["sam"], locked=True)
    return {"sam": a["sam"], "locked": True}


def reset_password(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    # A temporary credential would be delivered out of band. Nothing secret is
    # generated here or placed in the model's context.
    d.update(a["sam"], must_change_password=True)
    return {"sam": a["sam"], "status": "temporary credential issued out of band; change required at next sign-in"}


def disable_account(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    d.update(a["sam"], enabled=False)
    return {"sam": a["sam"], "enabled": False}


def enable_account(d: Directory, a: Dict[str, Any]) -> Dict[str, Any]:
    d.update(a["sam"], enabled=True)
    return {"sam": a["sam"], "enabled": True}


@dataclass(frozen=True)
class Tool:
    name: str
    risk: str  # read | medium | high
    check: Callable[[Dict[str, Any]], Dict[str, Any]]
    run: Callable[[Directory, Dict[str, Any]], Dict[str, Any]]
    target: Optional[str] = None  # which argument names the account/group acted on
    undo: Optional[str] = None  # name of the reverse tool, if any
    description: str = ""


REGISTRY: Dict[str, Tool] = {t.name: t for t in (
    Tool("lookup_user", "read", _sam, lookup_user, "sam", None, "Show one user's directory entry."),
    Tool("list_group_members", "read", _group, list_group_members, "group", None, "List the members of a group."),
    Tool("list_locked_accounts", "read", _none, list_locked_accounts, None, None, "List locked accounts."),
    Tool("unlock_account", "medium", _sam, unlock_account, "sam", "lock_account", "Unlock a locked account."),
    Tool("reset_password", "high", _sam, reset_password, "sam", None, "Issue a temporary credential."),
    Tool("disable_account", "high", _sam, disable_account, "sam", "enable_account", "Disable an account."),
)}

# Internal reverse operations: never offered to the planner, only used by undo.
_REVERSE: Dict[str, Tool] = {
    "lock_account": Tool("lock_account", "medium", _sam, lock_account, "sam"),
    "enable_account": Tool("enable_account", "medium", _sam, enable_account, "sam"),
}


def reverse_tool(name: str) -> Tool:
    return _REVERSE[name]

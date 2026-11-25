"""Authentication and role-based access control (deny by default).

API keys come from the LLM_LAB_API_KEYS environment variable, never from the
repository. Format: ``user:role:tenant:key`` entries separated by commas.
Keys must be at least 16 characters; placeholder values are ignored. With no
valid keys configured, every protected route answers 503 rather than running
open.
"""
from __future__ import annotations

import hmac
import logging
import os
from dataclasses import dataclass
from typing import Dict, FrozenSet, List

from fastapi import Depends, HTTPException, Request

from app.secure import audit

logger = logging.getLogger("llm_lab.secure.auth")

ROLE_PERMISSIONS: Dict[str, FrozenSet[str]] = {
    "viewer": frozenset({"chat:use", "usage:read", "rag:read"}),
    "editor": frozenset({"chat:use", "usage:read", "rag:read", "rag:write"}),
    "helpdesk": frozenset({"chat:use", "usage:read", "agent:use"}),
    "admin": frozenset({
        "chat:use", "usage:read", "rag:read", "rag:write", "rag:review", "audit:read", "config:read",
        "agent:use", "agent:approve",
    }),
}

MIN_KEY_LENGTH = 16


@dataclass(frozen=True)
class Principal:
    user: str
    role: str
    tenant: str

    def can(self, permission: str) -> bool:
        return permission in ROLE_PERMISSIONS.get(self.role, frozenset())


@dataclass(frozen=True)
class _Entry:
    principal: Principal
    key: str


def _load_entries() -> List[_Entry]:
    raw = os.environ.get("LLM_LAB_API_KEYS", "")
    entries: List[_Entry] = []
    for item in filter(None, (part.strip() for part in raw.split(","))):
        pieces = item.split(":", 3)
        if len(pieces) != 4:
            logger.warning("ignoring malformed API key entry")
            continue
        user, role, tenant, key = pieces
        if role not in ROLE_PERMISSIONS:
            logger.warning("ignoring API key entry with unknown role")
            continue
        if len(key) < MIN_KEY_LENGTH or "CHANGE_ME" in key:
            logger.warning("ignoring API key entry with a weak or placeholder key")
            continue
        entries.append(_Entry(Principal(user, role, tenant), key))
    return entries


def _match(presented: str) -> "Principal | None":
    found = None
    for entry in _load_entries():  # no early exit: constant work per entry
        if hmac.compare_digest(entry.key.encode(), presented.encode()) and found is None:
            found = entry.principal
    return found


def require(permission: str):
    """FastAPI dependency factory: authenticate, then authorize."""

    def dependency(request: Request) -> Principal:
        if not _load_entries():
            raise HTTPException(503, "Secure API is disabled: no valid API keys are configured.")
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        principal = _match(token.strip()) if scheme.lower() == "bearer" and token else None
        if principal is None:
            audit.LOG.record("auth_failed", user="anonymous", outcome="denied", path=request.url.path)
            raise HTTPException(401, "Missing or invalid credentials.", headers={"WWW-Authenticate": "Bearer"})
        if not principal.can(permission):
            audit.LOG.record(
                "authz_denied", user=principal.user, tenant=principal.tenant, outcome="denied",
                permission=permission, path=request.url.path,
            )
            raise HTTPException(403, "Your role does not permit this action.")
        return principal

    return Depends(dependency)

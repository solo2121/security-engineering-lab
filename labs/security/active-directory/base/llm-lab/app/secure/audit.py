"""Tamper-evident audit log.

Each event embeds the SHA-256 of the previous event, so removing or editing an
entry breaks the chain and verify() reports it. Raw prompts and responses are
never stored, only their length and a short hash, so the log does not become a
second copy of sensitive data.
"""

from __future__ import annotations

import hashlib
import json
import logging
import threading
import time
from collections import deque
from typing import Any, Deque, Dict, List, Optional

logger = logging.getLogger("llm_lab.audit")

GENESIS = "0" * 64


def fingerprint(text: str) -> Dict[str, Any]:
    return {"len": len(text), "sha256_8": hashlib.sha256(text.encode()).hexdigest()[:8]}


class AuditLog:
    def __init__(self, max_events: int = 1000) -> None:
        self._events: Deque[Dict[str, Any]] = deque(maxlen=max_events)
        self._lock = threading.Lock()
        self._last_hash = GENESIS

    def record(
        self, event: str, user: str, outcome: str, tenant: Optional[str] = None, **fields: Any
    ) -> Dict[str, Any]:
        with self._lock:
            body = {
                "ts": round(time.time(), 3),
                "event": event,
                "user": user,
                "tenant": tenant,
                "outcome": outcome,
                **fields,
                "prev": self._last_hash,
            }
            digest = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()
            body["hash"] = digest
            self._last_hash = digest
            self._events.append(body)
        logger.info(json.dumps(body, sort_keys=True))
        return body

    def events(self, event: Optional[str] = None, limit: int = 100) -> List[Dict[str, Any]]:
        with self._lock:
            items = [e for e in self._events if event is None or e["event"] == event]
        return items[-limit:]

    def verify(self) -> bool:
        """True if the retained events form an unbroken hash chain."""
        with self._lock:
            items = list(self._events)
        prev = items[0]["prev"] if items else GENESIS
        for item in items:
            body = {k: v for k, v in item.items() if k != "hash"}
            if body["prev"] != prev:
                return False
            if hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest() != item["hash"]:
                return False
            prev = item["hash"]
        return True

    def reset(self) -> None:
        with self._lock:
            self._events.clear()
            self._last_hash = GENESIS


LOG = AuditLog()

"""In-memory copy of the lab directory (loaded from data/ad/directory.json)."""
from __future__ import annotations

import copy
import json
import threading
from typing import Any, Dict, List, Optional

from app import config

PATH = config.DATA_DIR / "ad" / "directory.json"

# Accounts in these groups are protected: the helpdesk agent may read them
# but never change them, with or without approval.
PROTECTED_SUFFIXES = ("Admins",)
PROTECTED_GROUPS = frozenset({"Incident_Response", "Executive_Users"})


class Directory:
    def __init__(self, data: Dict[str, Any]) -> None:
        self._lock = threading.Lock()
        self.users: Dict[str, Dict[str, Any]] = {u["sam"]: copy.deepcopy(u) for u in data["users"]}
        self.groups: List[Dict[str, str]] = copy.deepcopy(data["groups"])

    def get(self, sam: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            u = self.users.get(sam)
            return copy.deepcopy(u) if u else None

    def is_protected(self, sam: str) -> bool:
        u = self.users.get(sam)
        if u is None:
            return False
        return any(g in PROTECTED_GROUPS or g.endswith(PROTECTED_SUFFIXES) for g in u["groups"])

    def is_protected_group(self, group: str) -> bool:
        return group in PROTECTED_GROUPS or group.endswith(PROTECTED_SUFFIXES)

    def members(self, group: str) -> List[str]:
        with self._lock:
            return sorted(s for s, u in self.users.items() if group in u["groups"])

    def locked(self) -> List[str]:
        with self._lock:
            return sorted(s for s, u in self.users.items() if u["locked"])

    def update(self, sam: str, **fields: Any) -> None:
        with self._lock:
            self.users[sam].update(fields)

    def snapshot(self) -> Dict[str, Dict[str, Any]]:
        with self._lock:
            return copy.deepcopy(self.users)


_dirs: Dict[str, Directory] = {}


def fresh() -> Directory:
    """A new copy of the seed data."""
    return Directory(json.loads(PATH.read_text(encoding="utf-8")))


def get(kind: str) -> Directory:
    if kind not in _dirs:
        _dirs[kind] = fresh()
    return _dirs[kind]


def reset() -> None:
    _dirs.clear()


def drop(kind: str) -> None:
    _dirs.pop(kind, None)

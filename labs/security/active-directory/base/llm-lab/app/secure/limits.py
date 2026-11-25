"""Per-principal rate limit and daily token budget (LLM06 Unbounded Consumption)."""
from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict

from fastapi import HTTPException

_lock = threading.Lock()
_windows: Dict[str, Deque[float]] = defaultdict(deque)
_tokens: Dict[str, Dict[str, int]] = defaultdict(lambda: {"day": 0, "used": 0})


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


def check_rate(user: str, limit: "int | None" = None, window: "int | None" = None) -> None:
    limit = limit if limit is not None else _int("LLM_LAB_SECURE_RATE_LIMIT", 10)
    window = window if window is not None else _int("LLM_LAB_SECURE_RATE_WINDOW", 60)
    now = time.monotonic()
    with _lock:
        q = _windows[user]
        while q and now - q[0] > window:
            q.popleft()
        if len(q) >= limit:
            raise HTTPException(429, "Rate limit exceeded.", headers={"Retry-After": str(window)})
        q.append(now)


def _today() -> int:
    return int(time.time() // 86400)


def check_budget(user: str, planned_tokens: int, budget: "int | None" = None) -> None:
    budget = budget if budget is not None else _int("LLM_LAB_SECURE_DAILY_TOKENS", 20_000)
    with _lock:
        rec = _tokens[user]
        if rec["day"] != _today():
            rec.update(day=_today(), used=0)
        if rec["used"] + planned_tokens > budget:
            raise HTTPException(429, "Daily token budget exhausted.")


def add_usage(user: str, tokens: int) -> None:
    with _lock:
        rec = _tokens[user]
        if rec["day"] != _today():
            rec.update(day=_today(), used=0)
        rec["used"] += tokens


def usage(user: str) -> Dict[str, int]:
    budget = _int("LLM_LAB_SECURE_DAILY_TOKENS", 20_000)
    with _lock:
        rec = _tokens[user]
        used = rec["used"] if rec["day"] == _today() else 0
    return {"tokens_used_today": used, "daily_token_budget": budget}


def reset() -> None:
    with _lock:
        _windows.clear()
        _tokens.clear()


def forget(user: str) -> None:
    """Drop one user's counters (used by throwaway defense checks)."""
    with _lock:
        _windows.pop(user, None)
        _tokens.pop(user, None)

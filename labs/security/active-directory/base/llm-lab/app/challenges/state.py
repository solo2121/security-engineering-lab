"""What the lab twins record so challenges can be verified."""

from __future__ import annotations

import time
from collections import deque
from typing import Any, Deque, Dict, List

lab_queries: Deque[float] = deque(maxlen=500)
lab_ungrounded = False
agent_runs: List[Dict[str, Any]] = []
last_render = ""
solved: Dict[str, float] = {}


def note_lab_query(top_score: float, min_score: float) -> None:
    global lab_ungrounded
    lab_queries.append(time.monotonic())
    if top_score < min_score:
        lab_ungrounded = True


def note_agent_run(request: str, steps: List[Dict[str, Any]]) -> None:
    agent_runs.append({"request": request, "steps": [{"tool": s["tool"], "args": s["args"]} for s in steps]})
    del agent_runs[:-50]


def note_render(html: str) -> None:
    global last_render
    last_render = html


def recent_queries(window: float = 60.0) -> int:
    cutoff = time.monotonic() - window
    return sum(1 for t in lab_queries if t >= cutoff)


def reset() -> None:
    global lab_ungrounded, last_render
    lab_queries.clear()
    agent_runs.clear()
    lab_ungrounded = False
    last_render = ""
    solved.clear()

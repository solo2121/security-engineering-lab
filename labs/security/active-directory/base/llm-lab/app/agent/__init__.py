"""Helpdesk agent working on a snapshot of the lab's Active Directory.

Two policies share the same tools and directory:
  secure  argument validation, tool allowlist per role, protected accounts,
          human approval for high-impact actions, step budget, audit, undo.
  lab     the confused-deputy version: it executes whatever the planner asks,
          including instructions hidden in directory data. Lab mode only.

Everything is simulated against an in-memory copy of the directory; no real
Active Directory is contacted and no password is ever generated or returned.
"""

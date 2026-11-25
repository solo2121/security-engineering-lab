#!/usr/bin/env python3
"""Build data/ad/directory.json from the lab's own DC provisioning script.

The agent works on a snapshot of the users and groups that dc01 creates
(provision/dc01/phase5-full-dc-config.ps1), so the data is the lab's real
structure. Passwords are never copied. Attacker-controlled attributes used by
the training scenarios live in data/ad/overlay.json, not in the provisioning
script. Run with --check to fail when the snapshot is stale.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "provision" / "dc01" / "phase5-full-dc-config.ps1"
OVERLAY = ROOT / "data" / "ad" / "overlay.json"
OUT = ROOT / "data" / "ad" / "directory.json"

PAIR = re.compile(r'(\w+)=("[^"]*"|@\([^)]*\))')


def parse(text: str) -> dict:
    users, groups = [], []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("@{Name="):
            continue
        fields = {k: v for k, v in PAIR.findall(line)}
        name = fields["Name"].strip('"')
        if "Pass" in fields and "Groups" in fields:
            users.append({
                "sam": name,
                "dept": fields.get("Dept", '""').strip('"'),
                "title": fields.get("Title", '""').strip('"'),
                "groups": re.findall(r'"([^"]+)"', fields["Groups"]),
                "manager": fields.get("Manager", '""').strip('"') or None,
            })
        elif "Description" in fields and "OU" in fields:
            groups.append({"name": name, "description": fields["Description"].strip('"')})
    return {"users": users, "groups": groups}


def build() -> str:
    data = parse(SOURCE.read_text(encoding="utf-8"))
    overlay = json.loads(OVERLAY.read_text()) if OVERLAY.exists() else {}
    for u in data["users"]:
        u.update({"enabled": True, "locked": False, "must_change_password": False, "description": ""})
        u.update(overlay.get(u["sam"], {}))
    data["source"] = "provision/dc01/phase5-full-dc-config.ps1 (passwords omitted)"
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    text = build()
    if "--check" in sys.argv:
        sys.exit(0 if OUT.read_text() == text else 1)
    OUT.write_text(text)
    data = json.loads(text)
    print(f"wrote {OUT}: {len(data['users'])} users, {len(data['groups'])} groups")

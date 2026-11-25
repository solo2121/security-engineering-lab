"""Embedded SQLite document and chunk store."""
from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
import time
from typing import Any, Dict, List, Optional

from app.rag import embed

CHUNK_CHARS = 600


def chunk(text: str, size: int = CHUNK_CHARS) -> List[str]:
    paras = [p.strip() for p in text.split("\n\n") if p.strip()]
    out: List[str] = []
    cur = ""
    for p in paras:
        if cur and len(cur) + len(p) + 2 > size:
            out.append(cur)
            cur = p
        else:
            cur = f"{cur}\n\n{p}" if cur else p
    if cur:
        out.append(cur)
    return [c[: size * 2] for c in out]


class Store:
    def __init__(self, path: str = ":memory:") -> None:
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self._db.executescript(
            """
            CREATE TABLE IF NOT EXISTS documents(
              id INTEGER PRIMARY KEY AUTOINCREMENT, tenant TEXT NOT NULL, title TEXT NOT NULL,
              version INTEGER NOT NULL, status TEXT NOT NULL, source TEXT, uploader TEXT,
              sha256 TEXT NOT NULL, flags TEXT NOT NULL DEFAULT '[]', created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS chunks(
              id INTEGER PRIMARY KEY AUTOINCREMENT, doc_id INTEGER NOT NULL, tenant TEXT NOT NULL,
              idx INTEGER NOT NULL, text TEXT NOT NULL, vec TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS chunks_tenant ON chunks(tenant);
            """
        )

    # -- writes ------------------------------------------------------------
    def add_document(self, tenant: str, title: str, text: str, source: str, uploader: str,
                     status: str = "active", flags: Optional[List[str]] = None) -> Dict[str, Any]:
        sha = hashlib.sha256(text.encode()).hexdigest()
        with self._lock:
            row = self._db.execute(
                "SELECT COALESCE(MAX(version),0) FROM documents WHERE tenant=? AND title=?", (tenant, title)
            ).fetchone()
            version = int(row[0]) + 1
            if status == "active":
                self._db.execute(
                    "UPDATE documents SET status='superseded' WHERE tenant=? AND title=? AND status='active'",
                    (tenant, title),
                )
            cur = self._db.execute(
                "INSERT INTO documents(tenant,title,version,status,source,uploader,sha256,flags,created)"
                " VALUES(?,?,?,?,?,?,?,?,?)",
                (tenant, title, version, status, source, uploader, sha, json.dumps(flags or []), time.time()),
            )
            doc_id = int(cur.lastrowid)
            for i, piece in enumerate(chunk(text)):
                vec = embed.embed(piece)
                if not embed.validate(vec):
                    self._db.rollback()
                    raise ValueError("embedding failed validation")
                self._db.execute(
                    "INSERT INTO chunks(doc_id,tenant,idx,text,vec) VALUES(?,?,?,?,?)",
                    (doc_id, tenant, i, piece, json.dumps(vec)),
                )
            self._db.commit()
        return self.get_document(doc_id)  # type: ignore[return-value]

    def set_status(self, doc_id: int, status: str) -> None:
        with self._lock:
            self._db.execute("UPDATE documents SET status=? WHERE id=?", (status, doc_id))
            self._db.commit()

    def activate(self, doc_id: int) -> None:
        """Make one version active and supersede the rest (rollback)."""
        with self._lock:
            d = self._db.execute("SELECT tenant,title FROM documents WHERE id=?", (doc_id,)).fetchone()
            self._db.execute(
                "UPDATE documents SET status='superseded' WHERE tenant=? AND title=? AND status='active'",
                (d["tenant"], d["title"]),
            )
            self._db.execute("UPDATE documents SET status='active' WHERE id=?", (doc_id,))
            self._db.commit()

    # -- reads -------------------------------------------------------------
    def get_document(self, doc_id: int) -> Optional[Dict[str, Any]]:
        with self._lock:
            r = self._db.execute("SELECT * FROM documents WHERE id=?", (doc_id,)).fetchone()
        return self._doc(r) if r else None

    def list_documents(self, tenant: Optional[str], status: Optional[str] = None) -> List[Dict[str, Any]]:
        q, args = "SELECT * FROM documents WHERE 1=1", []
        if tenant is not None:
            q += " AND tenant=?"
            args.append(tenant)
        if status:
            q += " AND status=?"
            args.append(status)
        with self._lock:
            rows = self._db.execute(q + " ORDER BY id", args).fetchall()
        return [self._doc(r) for r in rows]

    def search(self, query_vec: List[float], k: int, tenant: Optional[str], active_only: bool = True) -> List[Dict[str, Any]]:
        """Nearest chunks. tenant=None searches every tenant (lab mode only)."""
        q = ("SELECT c.text,c.vec,c.doc_id,c.tenant,d.title,d.version,d.status FROM chunks c "
             "JOIN documents d ON d.id=c.doc_id WHERE 1=1")
        args: List[Any] = []
        if tenant is not None:
            q += " AND c.tenant=?"
            args.append(tenant)
        if active_only:
            q += " AND d.status='active'"
        with self._lock:
            rows = self._db.execute(q, args).fetchall()
        scored = [
            {"doc_id": r["doc_id"], "tenant": r["tenant"], "title": r["title"], "version": r["version"],
             "text": r["text"], "score": embed.cosine(query_vec, json.loads(r["vec"]))}
            for r in rows
        ]
        scored.sort(key=lambda x: x["score"], reverse=True)
        return scored[:k]

    @staticmethod
    def _doc(r: sqlite3.Row) -> Dict[str, Any]:
        d = dict(r)
        d["flags"] = json.loads(d["flags"])
        return d

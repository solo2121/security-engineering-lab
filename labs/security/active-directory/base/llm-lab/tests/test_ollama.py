"""Provider tests against a fake Ollama server on localhost.

These exercise the real HTTP client code (requests, timeouts, bad responses)
without a model. They do not prove how a real model behaves.
"""
from __future__ import annotations

import json
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.main import create_app  # noqa: E402
from app.rag import embed, service  # noqa: E402
from app.secure import audit, gateway, limits  # noqa: E402


class Fake(BaseHTTPRequestHandler):
    calls: list = []
    chat_reply = {"message": {"content": "hello from the fake model"}, "prompt_eval_count": 11, "eval_count": 7}
    delay = 0.0
    garbage = False

    def log_message(self, *a):  # keep test output quiet
        pass

    def _send(self, obj, raw=None):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        Fake.calls.append(("GET", self.path, None))
        self._send({"models": [{"name": "llama3.2:1b"}, {"name": "nomic-embed-text:latest"}]})

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Fake.calls.append(("POST", self.path, payload))
        if Fake.delay:
            time.sleep(Fake.delay)
        if Fake.garbage:
            return self._send(None, raw=b"not json")
        if self.path == "/api/chat":
            return self._send(Fake.chat_reply)
        if self.path == "/api/embed":
            text = payload["input"].lower()
            vec = [float(text.count(w)) for w in ("leave", "expense", "roadmap", "refund", "days", "meal", "hotel", "sso")]
            return self._send({"embeddings": [vec if any(vec) else [0.1] * 8]})
        self.send_response(404)
        self.end_headers()


@pytest.fixture()
def fake(monkeypatch):
    Fake.calls = []
    Fake.delay = 0.0
    Fake.garbage = False
    Fake.chat_reply = {"message": {"content": "hello from the fake model"}, "prompt_eval_count": 11, "eval_count": 7}
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    monkeypatch.setenv("LLM_LAB_PROVIDER", "ollama")
    monkeypatch.setenv("LLM_LAB_OLLAMA_URL", f"http://127.0.0.1:{srv.server_address[1]}")
    service.reset()
    yield Fake
    srv.shutdown()
    service.reset()


@pytest.fixture()
def api(monkeypatch, fake):
    k = {n: secrets.token_hex(16) for n in ("alice", "root")}
    monkeypatch.setenv("LLM_LAB_API_KEYS", f"alice:viewer:tenant-a:{k['alice']},root:admin:tenant-a:{k['root']}")
    limits.reset()
    audit.LOG.reset()
    return TestClient(create_app("secure")), k


def hdr(key):
    return {"Authorization": f"Bearer {key}"}


def test_ollama_chat_sends_system_and_user_separately_with_a_token_cap(fake):
    out = gateway.complete("What is our leave policy?", 64)
    _, path, payload = [c for c in fake.calls if c[1] == "/api/chat"][0]
    assert [m["role"] for m in payload["messages"]] == ["system", "user"]
    assert payload["messages"][1]["content"] == "What is our leave policy?"
    assert payload["options"]["num_predict"] == 64 and payload["stream"] is False
    assert (out.provider, out.prompt_tokens, out.completion_tokens) == ("ollama", 11, 7)


def test_ollama_output_is_sanitised_and_capped(fake):
    fake.chat_reply = {"message": {"content": "a\x00b" + "x" * 500}}
    assert gateway.complete("hi", 10).text == "ab" + "x" * 38


def test_ollama_secure_chat_end_to_end(api):
    client, k = api
    r = client.post("/secure/chat", json={"prompt": "hello"}, headers=hdr(k["alice"]))
    assert r.status_code == 200 and r.json()["provider"] == "ollama" and r.json()["usage"]["completion_tokens"] == 7


def test_ollama_timeout_is_a_clean_502(api, monkeypatch):
    client, k = api
    Fake.delay = 1.5
    monkeypatch.setenv("LLM_LAB_PROVIDER_TIMEOUT", "0.3")
    r = client.post("/secure/chat", json={"prompt": "hello"}, headers=hdr(k["alice"]))
    assert r.status_code == 502 and "127.0.0.1" not in r.text


def test_ollama_garbage_response_is_a_clean_502(api):
    client, k = api
    Fake.garbage = True
    assert client.post("/secure/chat", json={"prompt": "hello"}, headers=hdr(k["alice"])).status_code == 502


def test_ollama_unreachable_is_a_clean_502(api, monkeypatch):
    client, k = api
    monkeypatch.setenv("LLM_LAB_OLLAMA_URL", "http://127.0.0.1:9")
    assert client.post("/secure/chat", json={"prompt": "hello"}, headers=hdr(k["alice"])).status_code == 502


def test_ollama_rejects_malformed_chat_shape(fake):
    fake.chat_reply = {"message": "not a dict"}
    with pytest.raises(gateway.ProviderUnavailable):
        gateway.complete("hi", 10)


def test_llm09_2026_ollama_embeddings_are_normalised_and_validated(fake):
    vec = embed.embed("leave days")
    assert len(vec) == 8 and embed.validate(vec, 8) and embed.embedder_id() == "ollama:nomic-embed-text"
    assert not embed.validate(vec, 16)


def test_llm09_2026_rag_with_ollama_embeddings_keeps_tenant_isolation(api):
    client, k = api
    from app.rag.store import Store

    st = Store()
    st.add_document("tenant-a", "a", "leave days policy", "s", "u")
    st.add_document("tenant-b", "b", "roadmap sso confidential", "s", "u")
    got = st.search(embed.embed("roadmap sso"), 5, "tenant-a")
    assert {g["tenant"] for g in got} == {"tenant-a"}


def test_llm09_2026_vectors_from_different_embedders_are_not_mixed(monkeypatch, fake):
    from app.rag.store import Store

    st = Store()
    st.add_document("t", "x", "leave days", "s", "u")  # embedded by the fake Ollama (8 dims)
    monkeypatch.setenv("LLM_LAB_PROVIDER", "mock")
    assert st.search(embed.embed("leave days"), 5, "t") == []  # hash-256 query ignores 8-dim vectors


def test_ollama_rag_query_end_to_end(api):
    client, k = api
    r = client.post("/secure/rag/query", json={"question": "how many leave days"}, headers=hdr(k["alice"]))
    assert r.status_code == 200
    assert any(c[1] == "/api/embed" for c in Fake.calls) and any(c[1] == "/api/chat" for c in Fake.calls)


def test_ollama_down_during_rag_is_a_clean_502(api, monkeypatch):
    client, k = api
    monkeypatch.setenv("LLM_LAB_OLLAMA_URL", "http://127.0.0.1:9")
    r = client.post("/secure/rag/query", json={"question": "leave"}, headers=hdr(k["alice"]))
    assert r.status_code == 502


def test_provider_check_reports_models_and_requires_admin(api):
    client, k = api
    assert client.get("/secure/admin/provider-check", headers=hdr(k["alice"])).status_code == 403
    body = client.get("/secure/admin/provider-check", headers=hdr(k["root"])).json()
    assert body["reachable"] is True and "llama3.2:1b" in body["models"]


def test_provider_check_reports_unreachable(api, monkeypatch):
    client, k = api
    monkeypatch.setenv("LLM_LAB_OLLAMA_URL", "http://127.0.0.1:9")
    assert client.get("/secure/admin/provider-check", headers=hdr(k["root"])).json()["reachable"] is False

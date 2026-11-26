# llm01 — OWASP Top 10 for LLM Applications Training Lab

> **⚠️ SAFETY WARNING**
> This application intentionally contains vulnerable code paths for education. It runs
> **only** on the isolated `llm01` VM, on the lab's private network. It must never be
> exposed to the public internet or run on a production host. Every "vulnerable"
> response uses synthetic data only (`FAKE-ONLY-`, `LAB_SECRET_`, `SYNTHETIC-` markers) —
> no real secrets, credentials, or personal information ever appear in this app, and no
> dangerous action (shell execution, arbitrary file access, package installation) is ever
> actually performed. See [Safety Model](#safety-model) below.

```text
API address:            http://172.28.128.60:8000
Swagger/OpenAPI address: http://172.28.128.60:8000/docs
VM name:                 llm01
Hostname:                llm01.lab.local
IP address:              172.28.128.60  (override: LLM01_IP)
Required profile:        llm  (or full)
Required memory:         4096 MB  (override: LLM01_MEMORY)
Required CPUs:            4      (override: LLM01_CPUS)
Required provider:       libvirt (KVM/QEMU) or VirtualBox
```

## Quick Start

```bash
# Just llm01, using the base lab's Vagrantfile
cd labs/security/active-directory/base
LAB_PROFILE=llm vagrant up llm01

# llm01 alongside the rest of the AD lab
LAB_PROFILE=full vagrant up

# SSH in
LAB_PROFILE=llm vagrant ssh llm01

# Check the service (the lab runs in Docker and starts by itself on every boot)
LAB_PROFILE=llm vagrant ssh llm01 -c "systemctl status llm-lab-docker --no-pager; docker ps"

# From the host, once the VM reports healthy
curl http://172.28.128.60:8000/health
open http://172.28.128.60:8000/docs   # Swagger UI (macOS `open`; use xdg-open on Linux)
```

## What starts automatically on llm01

`vagrant up llm01` leaves a working lab with nothing else to run:

- Docker is installed, the image is built from `docker-compose.yml`, and
  `llm-lab-docker.service` starts the container on every boot (no internet needed after
  provisioning). If Docker cannot be set up, provisioning falls back to the Python service
  (`llm-owasp-lab.service`) and says so.
- Provisioning waits for `/health` and only then reports success.
- Fresh random API keys are written to `/opt/llm-lab/.env` (root only, never in the repo).
  Read them inside the VM with `sudo cat /opt/llm-lab/.env`.
- Egress is restricted to the lab subnet for the host **and** for containers (Docker traffic
  bypasses the normal OUTPUT chain, so `llm01-egress` also sets `DOCKER-USER` rules). The
  `llm01-egress.service` unit reapplies them on every boot.
- The real local model is opt-in. `sudo llm01-ollama enable` opens egress only for the
  download (about 1.5 GB), closes it again, and switches the lab to Ollama.
  `sudo llm01-ollama disable` returns to the offline mock model.

## Run modes

| Mode | Set by | What runs |
|---|---|---|
| `secure` (default) | unset, or `LLM_LAB_MODE=secure` | Only the authenticated `/secure/*` baseline API |
| `lab` | `LLM_LAB_MODE=lab` | The baseline plus the intentionally vulnerable scenarios below |

The `llm01` VM's systemd unit sets `lab`, so the VM works exactly as before. A bare
`uvicorn app.main:app` now starts in `secure` mode. For the secure API, architecture,
threat model, test matrix, runbook and roadmap see [`docs/`](docs/).

## RAG with two tenants

Seed documents for two synthetic tenants (`tenant-a`, `tenant-b`) load at startup from
`data/rag/seed/`. In secure mode the API key decides the tenant:

```bash
curl -s http://127.0.0.1:8000/secure/rag/query -H "Authorization: Bearer $VKEY" \
  -H "Content-Type: application/json" -d '{"question": "How many days of annual leave do I get?"}'
```

Roles: `viewer` queries, `editor` uploads documents (`POST /secure/rag/documents`), `admin`
also releases quarantined uploads and rolls versions back. In `lab` mode `/lab/rag` offers the
vulnerable twin: a global index (cross-tenant leak), no ingestion checks, and retrieved text
mixed into the prompt, so `data/rag/samples/poisoned-faq.md` really does take over the answer.
Offline, the built-in mock model is deliberately gullible so these attacks are reproducible;
see [`docs/owasp-2026-coverage.md`](docs/owasp-2026-coverage.md).

## Helpdesk agent on the lab's Active Directory

`data/ad/directory.json` is a snapshot of the 48 users and 13 groups that dc01 creates
(passwords omitted), rebuilt with `python3 scripts/export_ad_snapshot.py`. No real AD is
contacted. Give a key the `helpdesk` role and ask the agent for something:

```bash
curl -s http://127.0.0.1:8000/secure/agent/run -H "Authorization: Bearer $HKEY" \
  -H "Content-Type: application/json" -d '{"request": "reset the password for mike.taylor"}'
# -> pending_approval; an admin other than the requester approves it:
curl -s -X POST http://127.0.0.1:8000/secure/agent/approvals/<id>/approve -H "Authorization: Bearer $AKEY"
```

Reads run directly, unlocks run and can be undone, and `reset_password` and `disable_account`
wait for a human. Executive and admin accounts can never be changed by the agent. In `lab`
mode, `POST /lab/agent/run {"request": "who is amanda.white"}` shows the confused deputy: a
note hidden in her description field makes the agent reset the CEO's password, and
`GET /lab/agent/state` shows what changed (`POST /lab/agent/reset` restores the seed).

## Challenges

In `lab` mode, `GET /challenges` lists ten challenges, one per 2026 risk. Attack the
vulnerable twin, `POST /challenges/{id}/verify`, then `POST /challenges/{id}/defense-check` to
replay the attack against the secure policy and see which controls stop it. Flags are unique
to each running instance. See [`docs/challenges.md`](docs/challenges.md).

## Docker Compose (local, optional)

```bash
cd labs/security/active-directory/base/llm-lab
cp .env.example .env        # then replace every CHANGE_ME key; the API stays off until you do
docker compose up -d --build                    # secure mode on http://127.0.0.1:8000
docker compose --profile lab up -d --build      # also the vulnerable lab on http://127.0.0.1:8001
docker compose down -v                          # teardown
```

Example call, using a key from your `.env`:

```bash
curl -s http://127.0.0.1:8000/secure/chat \
  -H "Authorization: Bearer $LAB_KEY" -H "Content-Type: application/json" \
  -d '{"prompt": "Summarize our leave policy.", "max_tokens": 128}'
```

The default provider is a deterministic offline mock, which is also deliberately gullible so
injection attacks are reproducible. To use a real local model through Ollama:

```bash
docker compose --profile ollama-pull run --rm ollama-pull   # once; the only step that needs internet
# in .env: LLM_LAB_PROVIDER=ollama
docker compose --profile ollama up -d
curl -s http://127.0.0.1:8000/secure/admin/provider-check -H "Authorization: Bearer $AKEY"
```

The `ollama` service sits on an internal-only network, so it cannot download anything itself;
that is why models are pulled by the separate one-shot service. Defaults are `llama3.2:1b` for
chat and `nomic-embed-text` for RAG embeddings (set in `.env`). With Ollama the RAG store
embeds with the real model, and a small real model will often follow, ignore or half-follow
an injected instruction, unlike the mock. Tests use the mock and a fake Ollama server, so the
real-model behavior is something to explore by hand. Switching provider needs a restart,
because the in-memory RAG store is built with one embedder.

## Taxonomy

The scenario modules were written against the OWASP Top 10 for LLM Applications 2025
numbering and keep their `/llmNN` endpoint prefixes. The current edition is the 2026
list (<https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/>). `GET /owasp/categories`
returns both, with `categories_2026` mapping each 2026 identifier onto the endpoints, and
[`docs/owasp-2026-coverage.md`](docs/owasp-2026-coverage.md) lists what each risk covers
today. The table below uses the 2025 numbering of the endpoints.

| Category | Scenario | Module | Endpoints | Test |
|---|---|---|---|---|
| LLM01 | Prompt Injection | `app/scenarios/llm01_prompt_injection.py` | `POST /llm01/chat` | `test_llm01_*` |
| LLM02 | Sensitive Information Disclosure | `app/scenarios/llm02_sensitive_information.py` | `GET /llm02/debug`, `GET /llm02/echo-with-context` | `test_llm02_*` |
| LLM03 | Supply Chain | `app/scenarios/llm03_supply_chain.py` | `GET /llm03/manifest` | `test_llm03_*` |
| LLM04 | Data and Model Poisoning | `app/scenarios/llm04_data_poisoning.py` | `POST /llm04/ingest`, `GET /llm04/validate/{id}`, `GET /llm04/sample-poisoned-doc` | `test_llm04_*` |
| LLM05 | Improper Output Handling | `app/scenarios/llm05_improper_output.py` | `POST /llm05/render`, `POST /llm05/simulated-query` | `test_llm05_*` |
| LLM06 | Excessive Agency | `app/scenarios/llm06_excessive_agency.py` | `POST /llm06/agent-task` | `test_llm06_*` |
| LLM07 | System Prompt Leakage | `app/scenarios/llm07_prompt_leakage.py` | `POST /llm07/chat`, `POST /llm07/refund` | `test_llm07_*` |
| LLM08 | Vector and Embedding Weaknesses | `app/scenarios/llm08_vector_embedding.py` | `POST /llm08/rag-query` | `test_llm08_*` |
| LLM09 | Misinformation | `app/scenarios/llm09_misinformation.py` | `GET /llm09/ask` | `test_llm09_*` |
| LLM10 | Unbounded Consumption | `app/scenarios/llm10_unbounded_consumption.py` | `POST /llm10/generate` | `test_llm10_*` |

**Legacy / supplemental** (older OWASP revision categories or techniques now folded into
the categories above — clearly labeled, never presented as current): `GET
/legacy/model-theft`, `POST /legacy/insecure-plugin`, `POST
/legacy/indirect-prompt-injection` in `app/scenarios/legacy_supplemental.py`.

Every scenario endpoint's docstring documents: vulnerability description, educational
objective, safe/simulated behavior, an example request, the expected result, the
defensive mitigation, the logging/detection point, and its test case — read the module
source directly, or browse the same information interactively at `/docs`.

## Architecture

```text
llm-lab/
├── app/
│   ├── main.py                 # FastAPI app, router wiring, request-size/timing middleware
│   ├── config.py                # env-driven configuration, sandbox paths, limits
│   ├── models.py                # shared Pydantic request/response models
│   ├── safety.py                # command allowlist, sandboxed paths, redaction, rate limiting
│   └── scenarios/                # one module per OWASP category + legacy_supplemental.py
├── data/
│   ├── documents/                # synthetic trusted + poisoned RAG documents
│   ├── fake_secrets/             # synthetic-only fixtures (FAKE-ONLY- / LAB_SECRET_ / SYNTHETIC-)
│   └── sandbox/                  # the only path the app is ever allowed to read/write
├── app/secure/                   # secure baseline: auth/RBAC, gateway, redaction, limits, audit
├── app/rag/                      # two-tenant RAG: embedded store, ingestion, secure and lab policies
├── app/agent/                    # helpdesk agent: tools, policy, approvals, lab twin
├── app/challenges/               # ten challenges: attack, verify, defense-check (lab mode)
├── data/rag/                     # synthetic seed documents and the poisoned sample
├── data/ad/                      # AD snapshot built from the dc01 provisioning script
├── docs/                         # architecture, threat model, coverage, test matrix, runbook, roadmap
├── tests/test_app.py             # scenario tests (33), lab mode
├── tests/test_secure.py          # secure baseline tests (33)
├── tests/test_rag.py             # RAG tests (24)
├── tests/test_ollama.py          # provider tests against a fake Ollama server (14)
├── tests/test_agent.py           # helpdesk agent tests (26)
├── tests/test_challenges.py      # challenge attack/verify/defense tests (41)
├── Dockerfile, docker-compose.yml, .env.example
├── scripts/smoke_test.sh          # curl-based smoke test against the running VM
├── systemd/llm-owasp-lab.service  # hardened systemd unit (fallback runtime on the VM)
├── systemd/llm-lab-docker.service # starts the Compose stack on boot
├── systemd/llm01-egress.service   # reapplies egress isolation on boot
└── requirements.txt               # pinned: fastapi, uvicorn, pydantic
```

## Safety Model

Every control below is enforced in `app/safety.py`, not left to individual scenario
authors to remember:

- **No real shell execution, ever.** `simulate_command()` only recognizes a fixed
  allowlist (`id`, `whoami`, `pwd`, `uname`, `echo`) and returns hardcoded/derived output
  — it never calls `subprocess`, `os.system`, or `eval`. Anything else, including
  `rm -rf /`, is rejected and logged, not executed.
- **No arbitrary file access.** `resolve_sandbox_path()` resolves every user-supplied
  path against `data/sandbox/` and raises `HTTPException(400)` on any attempt to escape
  it (absolute paths, `..`, symlink tricks).
- **No unsafe deserialization.** The supply-chain (LLM03) scenario validates a manifest's
  pinning/hash metadata; it never unpickles or `eval`s anything.
- **No real secrets.** Every value returned anywhere in the API is prefixed
  `FAKE-ONLY-`, `LAB_SECRET_`, or `SYNTHETIC-`. A test (`test_llm02_secrets_are_synthetic_only`)
  asserts this.
- **No unbounded output.** `config.MAX_TEXT_LENGTH`, `MAX_OUTPUT_LENGTH`, and
  `MAX_REQUEST_BYTES` cap every request/response; LLM10's `/llm10/generate` clamps
  requested output size and never actually generates it.
- **Rate limiting + quotas.** In-memory per-client rate limiting
  (`RATE_LIMIT_REQUESTS` / `RATE_LIMIT_WINDOW_SECONDS`) and a per-key daily quota
  (`DAILY_QUOTA`), enforced before any "work" happens.
- **No outbound internet from the app.** Nothing in `app/` makes an HTTP request,
  installs a package, or resolves a DNS name at runtime.
- **Secure by default.** Without `LLM_LAB_MODE=lab` the vulnerable scenarios are not
  mounted. The `/secure` API denies everything until valid keys are configured, and
  authenticates, authorizes, rate-limits, scans and audits every request.
- **OS-level defense in depth.** The systemd unit runs as an unprivileged `llmlab` user
  with `ProtectSystem=strict`, `ProtectHome=true`, and a single writable path
  (`data/sandbox`) — even a bug in the app can't write outside that directory.
- **Network isolation.** `llm01` sits on the lab's private, host-only/libvirt-isolated
  subnet like every other VM in this lab; it is provisioned with outbound internet
  access removed after package installation (see the Vagrantfile's `llm01` block).

## Testing Guide

```bash
# Local, in-process — no VM needed (what CI runs)
pip install -r labs/security/active-directory/base/llm-lab/requirements.txt --break-system-packages
pip install pytest httpx --break-system-packages
pytest labs/security/active-directory/base/llm-lab/tests/ -v

# Against the running VM, once it's up
LLM01_HOST=172.28.128.60 labs/security/active-directory/base/llm-lab/scripts/smoke_test.sh
```

The pytest suite (171 tests: 33 scenario tests in `test_app.py`, 33 secure-baseline tests in
`test_secure.py`, 24 RAG tests in `test_rag.py`, 14 provider tests in `test_ollama.py`, 26 agent
tests in `test_agent.py`, 41 challenge tests in `test_challenges.py`) covers: every scenario's vulnerable and defensive
behavior, the safety-module unit tests (command allowlist, sandbox-path traversal,
redaction, HTML encoding), input-size limits, rate limiting/quotas, and that
arbitrary-shell-execution and arbitrary-file-access attempts are refused rather than
silently succeeding.

## Defensive Controls Guide

Each scenario's `defensive_mode`/`enforce_authorization`/`redact`/`dry_run` parameter (see
the table above) demonstrates one concrete, working mitigation next to the vulnerable
default — instruction separation (LLM01), output redaction (LLM02), integrity hashing
(LLM04), output encoding (LLM05), an authorization allowlist (LLM06), moving business
logic out of the prompt (LLM07), authorization-aware retrieval filtering (LLM08),
citation/confidence requirements (LLM09), and bounded resource controls (LLM10) — so
learners can diff the two code paths directly instead of taking the fix on faith.

## Reset and Cleanup

```bash
# Reset in-memory scenario state (rate limits, ingested documents) — just restart the service
LAB_PROFILE=llm vagrant ssh llm01 -c "sudo systemctl restart llm-lab-docker"

# Destroy just this VM
LAB_PROFILE=llm vagrant destroy llm01 -f
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `vagrant up llm01` says "machine not found" | `llm01` isn't in your active `LAB_PROFILE` | `LAB_PROFILE=llm vagrant up llm01` or `LAB_PROFILE=full vagrant up` |
| `curl` to port 8000 times out | Provisioning still running, or VM booted without network up yet | `LAB_PROFILE=llm vagrant ssh llm01 -c "systemctl status llm-owasp-lab"`; wait for `apt-get`/`pip` provisioning to finish |
| `systemctl status llm-lab-docker` shows failed | Check `journalctl -u llm-lab-docker -n 50 --no-pager` and `docker compose -f /opt/llm-lab/docker-compose.yml logs --tail 50` | Re-run `vagrant provision llm01`; if Docker cannot be installed, provisioning uses `llm-owasp-lab` instead |
| `llm01-ollama enable` fails to download | The VM has no route to the internet | Check DNS and the host network, then run it again; egress is closed again either way |
| `/docs` returns 404 | App didn't start (see above) | Same as above |

## Portfolio Note

This lab demonstrates: threat-modeling an LLM application against the current OWASP
taxonomy, building safety controls as a shared library rather than duplicating
allowlist/sandbox logic per scenario, keeping a training app's claims about its own
taxonomy self-verifying (`/owasp/categories`), and integrating a new intentionally
vulnerable service into an existing multi-VM lab without touching any of the other 10
VMs' provisioning.

# Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1. Secure baseline | Run modes, 2026 taxonomy map, auth/RBAC, gateway with mock and Ollama, redaction, injection scoring, rate limits and budgets, audit chain, Docker Compose, tests, threat model, runbook | Done |
| 2. RAG | Embedded SQLite store, ingestion with provenance, quarantine and versioning, tenant-filtered retrieval, citations; vulnerable `/lab/rag` counterpart. Secure controls and tests for LLM05, LLM07, LLM09 and indirect LLM01 | Done |
| 2b. Real model | Ollama chat and embeddings with a host allowlist, timeouts, clean failures, a provider check and a one-shot model-pull service. Not yet verified against a real Ollama server | Done (untested against a live model) |
| 3. Agents and tools | Helpdesk agent on a snapshot of the lab's AD: tool registry, protected accounts, human approval, step budget, undo; vulnerable `/lab/agent` twin | Done |
| 4. Observability | OpenTelemetry traces and metrics, structured logs to Loki, Grafana dashboards, alert rules matching the runbook | Planned |
| 5. Deployment and supply chain | Kubernetes manifests (NetworkPolicy, restricted PodSecurity), SBOM, image scanning and signing in CI, blocking lint and type checks | Planned |
| 6. Admin dashboard | Users, usage, audit log, model config and security events in a small UI | Planned |

Each phase ships as its own reviewed change so the working `llm01` VM is never
at risk from a large rewrite.

# Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1. Secure baseline | Run modes, 2026 taxonomy map, auth/RBAC, gateway with mock and Ollama, redaction, injection scoring, rate limits and budgets, audit chain, Docker Compose, tests, threat model, runbook | Done |
| 2. RAG | Document ingestion, vector store (pgvector or Qdrant), per-tenant namespaces, metadata authorization, citations. Adds secure controls and tests for LLM05, LLM07, LLM09 | Planned |
| 3. Agents and tools | Tool registry with allowlists, scoped credentials, human approval workflow, rollback. Adds LLM03 controls and indirect-injection tests | Planned |
| 4. Observability | OpenTelemetry traces and metrics, structured logs to Loki, Grafana dashboards, alert rules matching the runbook | Planned |
| 5. Deployment and supply chain | Kubernetes manifests (NetworkPolicy, restricted PodSecurity), SBOM, image scanning and signing in CI, blocking lint and type checks | Planned |
| 6. Admin dashboard | Users, usage, audit log, model config and security events in a small UI | Planned |

Each phase ships as its own reviewed change so the working `llm01` VM is never
at risk from a large rewrite.

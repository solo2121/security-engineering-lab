# Threat model

Scope: the secure baseline (`/secure/*`) as built. Components not built yet are
listed in the [roadmap](roadmap.md) and get their own rows when they land.
Each threat names the control that answers it and the test that proves it. See
the [test matrix](test-matrix.md).

## API and authentication

| Threat | Control | Evidence |
|---|---|---|
| Call the API without credentials | Deny by default; 503 when no keys configured, 401 on bad key | `test_llm03_2026_*` |
| Brute-force or time a key | Constant-time compare over every entry, per-user rate limit | `auth._match`, `test_llm06_2026_rate_limit` |
| Weak or default key shipped | Keys under 16 chars and `CHANGE_ME` placeholders are ignored | `test_llm03_2026_placeholder_and_short_keys_are_ignored` |
| Privilege escalation to admin routes | Permission check per route, denials audited | `test_llm03_2026_viewer_cannot_read_audit_or_config` |
| Mass assignment through the request body | `extra="forbid"` schemas | `test_llm10_2026_request_schema_is_strict` |

Residual risk: static API keys have no expiry or per-key revocation list. Move to OIDC or short-lived tokens before any shared deployment.

## Injection filter

| Threat | Control | Evidence |
|---|---|---|
| Direct override ("ignore previous instructions") | Heuristic score, block at threshold, audit | `test_llm01_2026_injection_is_blocked_and_audited` |
| Spoofed system delimiters | `delimiter_spoof` rule | `test_llm01_2026_delimiter_spoofing_is_flagged` |
| Legitimate prompts blocked | Threshold tuned so a single weak signal does not block | `test_llm01_2026_benign_prompt_scores_low` |

Residual risk: heuristics are bypassed by paraphrase, encoding and other languages. The structural controls (fixed system message, user text as data, no tools without authorization, output handling) carry the real weight. Indirect injection through documents and tool output arrives with the RAG and agent phases.

## Redaction and audit

| Threat | Control | Evidence |
|---|---|---|
| PII or credentials sent to the model | Input redaction | `test_llm02_2026_prompt_pii_is_redacted_before_the_model` |
| Model emits sensitive-looking data | Output scan | `test_llm02_2026_model_output_is_scanned` |
| Audit log becomes a data store | Length and hash only | `test_llm02_2026_audit_stores_fingerprint_not_prompt` |
| Audit tampering | Hash chain with verification | `test_xcut_audit_chain_detects_tampering` |
| Config endpoint leaks keys | Non-secret fields only | `test_llm02_2026_admin_config_never_returns_keys` |

Residual risk: the chain is in memory and resets on restart. Ship events to append-only external storage for real retention. Regex redaction misses reworded or encoded data.

## Gateway and provider

| Threat | Control | Evidence |
|---|---|---|
| SSRF through the provider URL | Host allowlist | `test_xcut_ollama_url_is_allowlisted` |
| Cost abuse, token exhaustion | Per-user rate limit, daily token budget, `max_tokens` cap | `test_llm06_2026_*` |
| Hung provider | Request timeout | `LLM_LAB_PROVIDER_TIMEOUT` |
| Provider error leaks internals | Generic 502, detail only in audit | `test_llm06_2026_provider_failure_is_a_clean_502` |
| Output treated as markup or code | Plain text, control characters removed, `nosniff` | `test_llm10_2026_*` |

## RAG pipeline

| Threat | Control | Evidence |
|---|---|---|
| Cross-tenant retrieval | Tenant filter in the SQL query, tenant from the credential, never the request | `test_llm09_2026_tenant_isolation_in_retrieval` |
| Guessing another tenant's document ids | 404 for ids outside the caller's tenant | `test_llm09_2026_cross_tenant_document_ids_look_nonexistent` |
| Poisoned upload | Role-gated writes, size limit, injection scan, quarantine | `test_llm05_2026_poisoned_upload_is_quarantined_not_indexed` |
| Poisoned chunk already indexed | Re-scan at retrieval, excluded and audited | `test_llm01_2026_indirect_injection_excluded_at_retrieval` |
| Silent corpus change | Versions, provenance, hash, rollback | `test_llm05_2026_versioning_and_rollback` |
| Fabricated or missing citations | Citation check, refusal without evidence | `test_llm07_2026_*` |
| Malformed embeddings | Validation before insert | `test_llm09_2026_malformed_vectors_are_rejected` |

Residual risk: the embedder is a hashing model, not a trained one, so retrieval quality is basic. The injection scan is heuristic: a well-paraphrased instruction can be indexed, and the structural defenses (documents wrapped as data, no tools in this path, output scanning) are what limit the damage. Tenant isolation here relies on one SQL filter; a real deployment should add database-level separation or row-level security.

## Container and deployment

| Threat | Control |
|---|---|
| Compromised process writes to the image | Read-only root filesystem, `/tmp` as tmpfs |
| Privilege escalation | Non-root user, all capabilities dropped, `no-new-privileges` |
| Exposure beyond the host | Ports bound to `127.0.0.1` only |
| Vulnerable scenarios exposed by accident | Not mounted unless `LLM_LAB_MODE=lab`; separate compose profile |
| Model server reachable from outside | `ollama` service sits on an internal-only network |

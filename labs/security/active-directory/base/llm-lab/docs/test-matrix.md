# Test matrix

Maps every secure-baseline test in [`tests/test_secure.py`](../tests/test_secure.py) to the OWASP Top 10 for LLM Applications 2026 risk it exercises. Pass criterion for every row: the test passes in CI (`pytest tests/ -v`); a failure means the control regressed.

| Test | Risk | What a pass proves |
|---|---|---|
| `test_llm03_2026_secure_api_disabled_without_keys` | LLM03 Excessive Agency | With no keys configured the API refuses to run open (503). |
| `test_llm03_2026_missing_or_wrong_token_is_401` | LLM03 Excessive Agency | Unauthenticated and wrong-key requests are rejected and audited. |
| `test_llm03_2026_viewer_cannot_read_audit_or_config` | LLM03 Excessive Agency | A low-privilege role cannot reach admin routes (403) and the denial is audited. |
| `test_llm03_2026_placeholder_and_short_keys_are_ignored` | LLM03 Excessive Agency | Placeholder and weak keys never become valid credentials. |
| `test_llm03_2026_unknown_role_is_ignored` | LLM03 Excessive Agency | An unknown role grants nothing (deny by default). |
| `test_llm10_2026_chat_returns_structured_plain_text` | LLM10 Improper Output Handling | Responses are a typed schema marked text/plain with nosniff and no-store. |
| `test_llm10_2026_request_schema_is_strict` | LLM10 Improper Output Handling | Unknown fields and oversized max_tokens are rejected. |
| `test_llm10_2026_control_characters_are_stripped` | LLM10 Improper Output Handling | Output is sanitized and handled as plain text, never rendered. |
| `test_llm01_2026_injection_is_blocked_and_audited` | LLM01 Prompt Injection | Override/reveal attacks are blocked, and the audit event holds no raw prompt. |
| `test_llm01_2026_benign_prompt_scores_low` | LLM01 Prompt Injection | Normal questions are not blocked (false-positive guard). |
| `test_llm01_2026_delimiter_spoofing_is_flagged` | LLM01 Prompt Injection | Fake system/instruction delimiters are detected. |
| `test_llm02_2026_redaction_rules` | LLM02 Sensitive Information Disclosure | Each PII/credential rule redacts its target (6 cases). |
| `test_llm02_2026_prompt_pii_is_redacted_before_the_model` | LLM02 Sensitive Information Disclosure | Sensitive values never reach the provider. |
| `test_llm02_2026_model_output_is_scanned` | LLM02 Sensitive Information Disclosure | Sensitive-looking output is redacted before it leaves the API. |
| `test_llm02_2026_audit_stores_fingerprint_not_prompt` | LLM02 Sensitive Information Disclosure | The audit log does not become a second copy of user data. |
| `test_llm02_2026_admin_config_never_returns_keys` | LLM02 Sensitive Information Disclosure | Config endpoint exposes no secrets. |
| `test_llm02_2026_usage_is_scoped_to_caller` | LLM02 Sensitive Information Disclosure | Users see only their own usage and tenant. |
| `test_llm06_2026_rate_limit` | LLM06 Unbounded Consumption | Requests over the per-user limit get 429. |
| `test_llm06_2026_daily_token_budget` | LLM06 Unbounded Consumption | A request that would exceed the daily token budget is refused. |
| `test_llm06_2026_limits_are_per_user` | LLM06 Unbounded Consumption | One user's traffic does not consume another's allowance. |
| `test_llm06_2026_provider_failure_is_a_clean_502` | LLM06 Unbounded Consumption | Provider errors do not leak internal details. |
| `test_xcut_ollama_url_is_allowlisted` | Cross-cutting hardening | The gateway cannot be pointed at arbitrary hosts (SSRF guard). |
| `test_xcut_audit_chain_detects_tampering` | Cross-cutting hardening | Editing a retained audit event breaks chain verification. |
| `test_mode_secure_hides_vulnerable_scenarios` | Run modes / taxonomy | Secure mode does not expose the vulnerable scenarios. |
| `test_mode_lab_mounts_both` | Run modes / taxonomy | Lab mode mounts both the scenarios and the secure API. |
| `test_default_mode_is_secure` | Run modes / taxonomy | Unset or unknown mode falls back to secure. |
| `test_taxonomy_2026_maps_every_category_to_a_live_endpoint` | Run modes / taxonomy | Every 2026 category maps to a real endpoint prefix. |

The 33 original scenario tests in `tests/test_app.py` cover the intentionally vulnerable modules and their built-in defensive switches under the 2025 numbering; see the mapping in [owasp-2026-coverage.md](owasp-2026-coverage.md).

## Not yet covered

LLM05 (poisoning), LLM07 (misinformation), LLM08 (hidden context) and LLM09 (vector/embedding) have scenario modules but no secure-baseline tests yet. They arrive with the RAG phase in the [roadmap](roadmap.md).

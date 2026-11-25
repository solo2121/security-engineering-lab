# Operations runbook

Applies to the secure baseline. Alerts below are defined against the audit
events and log fields that exist today; metrics-based alerts arrive with the
observability phase.

## Alerts

| Signal | Source | Suggested threshold | First action |
|---|---|---|---|
| Repeated injection attempts | `injection_blocked` events | 3 or more per user in 10 minutes | Review the user's recent events; revoke the key if the pattern continues |
| Authentication failures | `auth_failed` events | 10 or more in 5 minutes from any source | Check for key guessing; rotate keys if a valid key may be exposed |
| Permission denials | `authz_denied` events | Any for an admin permission | Identify the key and confirm the role |
| Token or cost anomaly | `tokens` in `chat` events, `/secure/usage` | A user above 3x their usual daily tokens | Lower `LLM_LAB_SECURE_DAILY_TOKENS`; contact the owner |
| Rate-limit pressure | HTTP 429 responses | Sustained 429s for one user | Confirm whether it is a runaway client |
| Possible exfiltration | `redactions` non-empty on many `chat` events | Sudden rise for one user | Review prompts' fingerprints and the data source |
| Agent denials or flagged data | `agent_tool_denied`, `agent_output_flagged` events | Any `agent_output_flagged`, or 3 or more denials per user in 10 minutes | Look at the directory field that was flagged and who last edited it; review the user's agent runs |
| Approval anomalies | `agent_self_approval_denied`, many `agent_approval_requested` | Any self-approval attempt, or a burst of requests | Review the requester; reject pending approvals you did not expect |
| Audit chain broken | `chain_valid: false` from `/secure/admin/audit` | Any | Treat as tampering; preserve logs and the container |

## Incident response

1. **Contain.** Remove the affected key from `LLM_LAB_API_KEYS` and restart: `docker compose up -d --force-recreate llm-lab`. For a runaway cost, set `LLM_LAB_SECURE_DAILY_TOKENS` low first.
2. **Preserve.** Save container logs (`docker compose logs llm-lab > incident.log`) and the audit output (`GET /secure/admin/audit?limit=500`). The in-memory chain is lost on restart, so capture it before recreating the container.
3. **Scope.** Filter events by user and `request_id`. Prompts are stored only as length and short hash, so correlate with the client's own records.
4. **Eradicate.** Rotate every key that may have been exposed. Review `.env` handling and any place the key was pasted.
5. **Recover.** Redeploy from a known-good image tag and confirm `/health` and `/secure/admin/config`.
6. **Review.** Add a test that reproduces the issue, and update the [threat model](threat-model.md).

## Procedures

**Backup.** The secure baseline is stateless. Back up `.env` (in a secrets manager, not git) and your compose file. The `lab-sandbox` volume holds only synthetic data.

**Rollback.** Images are tagged; redeploy the previous tag: `docker compose up -d` after pinning `image:` to the earlier tag, or `git checkout <tag>` and rebuild.

**Model update.** Change `LLM_LAB_OLLAMA_MODEL`, pre-pull the model (see the README), restart, then run the test suite. The tests use the mock provider, so also send a few manual prompts and check latency and answer quality.

**Dependency update.** Edit `requirements.txt` (versions stay pinned), run `pytest tests/ -v`, rebuild the image, and check the CI dependency and secret scans before merging.

**Key rotation.** Generate a new key (`python3 -c "import secrets; print(secrets.token_urlsafe(32))"`), update `.env`, recreate the container, and distribute the new key privately.

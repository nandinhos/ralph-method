# RFC — Provider Failover and Fail-Fast on Rate Limit

**Status:** ARCHIVED — supersedido pelo ADR-0016  
**Author:** Antigravity / Beer and Code Harness  
**Target:** Ralph Method Core (`ralph-control`, `ralph-init`)

> **Nota de arquivamento (2026-08-16):**
> O [`ADR-0016`](../../adr/0016-failover-controlado-entre-providers.md) já
> decide o fallback automático como **failover controlado pelo controlador**
> (opção C), com `fallback_policy=none` como default e cadeia
> `explicit_failover` por opt-in versionado — portanto o item 2 deste RFC
> (fallback automático `auto`) está coberto e não será implementado na forma
> proposta. O item 1 (`--fail-fast-on-limit`) é compatível com o ADR-0016 e
> fica disponível para avaliação futura como opção da `execution_policy`
> (`when_chain_exhausted`), sem compromisso de implementação. O item 3
> (telemetria streaming) permanece fora de escopo por decisão própria.
> Este arquivo é referência histórica; não é plano ativo.

---

## 1. Problem Statement

When a configured LLM provider CLI (e.g., `codex`) encounters rate limits or quota exhaustion, `ralph-control` enters a prolonged backoff retry loop (`limit_wait`, up to 20 cycles) without notifying the operator interactively or falling back to other healthy providers defined in `providers.json`.

In assisted interactive developer sessions, this causes the process to hang for tens of minutes without clear failure signals.

---

## 2. Proposed Solutions

1. **Option `--fail-fast-on-limit` in `ralph-control run` and `supervise`:**
   - If a provider reports `limit_wait`, immediately exit with code `429` (or `75` EX_TEMPFAIL) instead of blocking for 20 cycles.

2. **Automatic Provider Fallback Policy:**
   - Allow `fallback_policy: "auto"` in `method.json` / `install-manifest.json`.
   - When the primary provider fails due to rate limits or auth errors, attempt the next functional provider (`agy`, `opencode`, `claude`) in order of priority.

3. **Telemetry Streaming for Harness Adapters:**
   - Standardize a feedback event hook or exit code so external harnesses (Antigravity, OpenCode, Claude Code) can surface warning banners directly into the user chat.

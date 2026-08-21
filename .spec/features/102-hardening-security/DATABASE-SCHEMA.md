# FEATURE-102 — Database Schema (artefatos e fixtures de prova)

A Onda 2 não introduz schema de banco de dados novo. O "schema" aqui é a
lista de **artefatos e fixtures de prova** que cada feature deve produzir
para que os 5 gates da fase possam ser avaliados de forma mensurável.

## 1. Fixtures de redação (Feature 102A)

### `tests/fixtures/redaction/canary-text.txt`

Texto com padrões sensíveis usados no gate `quality` (suite `tests/test-sanitize-redact.sh`)
e no gate `runtime_evidence`:

```
github_token=ghp_abc123exampleREPLACEme
aws_secret=AKIAEXAMPLE/verysecret
INNER_/PATH/with-private-key-pem
db_url=postgres://user:pwd@host/db
```

Saída esperada do `sanitize()` (não guardar valor real):

```
github_token=[REDACTED:token]
aws_secret=[REDACTED:aws_secret]
INNER_/PATH/[REDACTED:private_key]/INNER_/PATH/with-private-key-pem
db_url=[REDACTED:db_url]
```

Estrutura canônica do evento `event.redacted` no ledger:

```json
{
  "type": "event.redacted",
  "facts": {
    "redacted_count": 4,
    "redacted_kinds": ["token","aws_secret","private_key","db_url"],
    "path": "/path/of/source",
    "feature_key": "FEATURE-102A-SANITIZE-REDACT",
    "attempt": 1
  }
}
```

> O caminho exato e o trecho redigido **nunca** vão para o ledger; só
> `facts.redacted_count`, `facts.redacted_kinds`, e `facts.path`.

## 2. Provas do Cursor em campo (Feature 102B)

### Estrutura de `provider-status` (read-only) — campos por adapter

```json
{
  "cursor": {
    "optin": true,
    "adversarial": false,
    "hero": false,
    "promoted": false,
    "promotion_blockers": ["adversarial", "hero"]
  }
}
```

### `tests/cursor-promotion-state.json` (snapshot canônico)

Antes da Onda 2: `{"optin": true, "adversarial": false, "hero": false,
"promoted": false}`. Após adversarial+hero aprovados: `{"optin": true,
"adversarial": true, "hero": true, "promoted": true}`.

### `docs/adr/ADR-0033-cursor-promotion.md`

ADR novo registrando a decisão de manter opt-in mas bloquear uso em produção
até prova reprodutível. Cobre:

- Contexto: opt-in declarado da FEATURE-100A, sem adversarial+hero completos.
- Decisão: manter opt-in (não banir), mas exigir `test-cursor-adversarial` +
  `test-cursor-hero` para `promoted=true`.
- Consequências: rebaixamento automático para opencode quando rebaixado;
  sem `promoted=true`, `--engine cursor` retorna `fail('cursor rebaixado')`.

## 3. Estado de policy divergence (Feature 102C)

### `tests/fixtures/policy/divergence.json`

Exemplo de execution_policy congelado com hash divergente do corrente:

```json
{
  "frozen_hash": "sha256:abc...ZERO",
  "current_hash": "sha256:def...CURR",
  "divergence": true,
  "expected_behavior": {
    "approveFeature": "rejeita com 'execution_policy divergiu'",
    "supervisor_before_retry": "registra recovery.required/policy_violation",
    "attempt_count": 0,
    "feature_status": "policy_violation"
  }
}
```

### Métrica contínua da Onda 2 (gate `runtime_evidence`)

```
grep -c '"cause_kind": *"feature_bug".*policy_violation' .git/ralph-control/events.jsonl
```

Esperado: `0` ao final da onda.

## 4. Enum canônica de tipos de evento (Feature 102D)

### `RALPH_KNOWN_EVENT_TYPES` (em `bin/ralph-control`)

```
workflow.initialized
workflow.policy.frozen
feature.claimed, feature.advanced, feature.approved, feature.released
attempt.started, block.finished
gate.started, gate.passed, gate.rejected, gate.retry_started, gate.stalled
recovery.required, recovery.retry_started, recovery.resolved
debugging.required, debugging.started, debugging.verified, debugging.rejected
delegation.started, delegation.completed, delegation.failed
telemetry.activity, telemetry.heartbeat_rich, telemetry.redacted
knowledge.candidate_created, knowledge.telemetry, knowledge.curated
knowledge.review_required, knowledge.skipped
harness_defect, policy.failed
event.rejected
command.started, command.heartbeat, command.finished, command.terminated
handoff.generated, handoff.committed
```

### `tests/fixtures/events/known-types.json`

Lista canônica dos tipos acima (29 tipos) — fixture usada pelo gate
`validation` para validar que tipos legados continuam funcionando e tipos
novos estão catalogados. Evento com tipo não-canônico → `event.rejected` e
não propaga.

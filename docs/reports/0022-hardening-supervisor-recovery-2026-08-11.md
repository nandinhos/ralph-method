# RPT-2026-0022 — Hardening de recovery do supervisor

## Objetivo

Corrigir a pane observada na revisão read-only do OpenCode e comprovar que o
supervisor continua determinístico, auditável e seguro após stale.

## Resultado

| Verificação | Resultado | Evidência |
|---|---|---|
| Retry stale produz novo `attempt` | aprovado | `scripts/test-ralph-method.sh` |
| Retry stale produz novo lease | aprovado | hashes de `feature.claimed` distintos |
| Fencing anterior não é reutilizado | aprovado | nova chamada a `beginFailedRetry()` |
| Árvore parcial é preservada | aprovado | `preserve-tree=true` no retry |
| Revisão read-only longa emite heartbeat | aprovado | `facts.phase=verification` |
| Regressão OpenCode impl/verify | aprovado | `scripts/test-ralph-reconciliation.sh` |
| CI portátil | aprovado | `bash scripts/ci-portable.sh` — 163 asserts |

## Sequência causal corrigida

```text
processo stale
→ grupo encerrado
→ recovery.required idempotente
→ novo attempt + novo lease + novo fencing
→ bloco único retomado
→ gates revalidados
```

## Limites

Este relatório não promove a `FEATURE-093` sozinho. A promoção continua
dependendo da execução real do workflow, dos cinco gates, do handoff e da
revisão/curadoria já configuradas pelo `ralph-control`.

## Referências

- ADR-0013 — retry do supervisor com novo fencing e heartbeat de verificação;
- Incidente 0013 — retry stale reutilizava lease e ocultava revisão longa;
- commit de implementação da feature anterior: `72831ee`.

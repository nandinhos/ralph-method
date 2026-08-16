# Relatório 0028 — candidata da FEATURE-094 (failover controlado Codex → OpenCode)

**Versão candidata:** sobre a base `0.9.2` + commits das fases 1–8
**Commit de referência:** `39ea59c` (fases 1–7) + matriz adversarial (Phase 8)
**Data:** 2026-08-16
**Status:** candidata — prova de campo (Phase 9) **concluída**; revisão adversarial independente **realizada** sem finding crítico/alto; promoção **pendente** do fluxo de release do Ralph (Phase 9, task 7).

## Resultado

A FEATURE-094 torna operacional a continuidade Codex → OpenCode quando o
Codex confirma `provider_usage_limited` de alta confiança e o workflow opta
pela política `explicit_failover`. O default permanece `fallback_policy=none`;
workflows sem a política mantêm exatamente o comportamento legado.

Este relatório separa o que foi comprovado por **fixture offline** (fases 1–8),
o que foi comprovado **em campo** (Phase 9) e o que permanece **pendente** da
promoção.

## Fixture comprovada (offline, sem rede/credenciais/geração real)

| Capacidade | Prova |
|---|---|
| runner-result v2 (`codex`/`claude`/`opencode`, `profile`, `failure_domain`, `usage_limited` high) com validação fail-closed; v1/v1.1 lidos e campos v2 rejeitados em legado | `test-provider-failover.sh` (jsonschema + importação PHP real) |
| `execution_policy` validada no `init` e hash congelado; drift bloqueia claim | fixture de drift |
| readiness expõe `failure_domain` opaco (`declared`/`unavailable`), sem valor bruto | fixture multiprovider |
| circuitos `closed\|open\|half_open` derivados só do ledger + relógio injetável | fixture + `RALPH_TEST_CLOCK_EPOCH` |
| `provider-status` e `failover-plan` somente leitura (sem mutar ledger) | fixture |
| loop nativo publica `usage_limited` e devolve ao controlador sem dormir/relançar | fixture com mensagem real do Codex |
| **failover real** `provider.capacity_limited` → `continuation.generated` (cápsula com fingerprint da árvore) → `provider.failover_started` (nova attempt/lease/fencing) → OpenCode inicia a continuação | `supervise` em fixture com fake codex/opencode + proof opencode |
| espera de capacidade reapropriável: cooldown, half-open, `max_no_progress_seconds` → recovery | relógio injetado |
| handoff com `provider_transitions`, monitor com circuitos, métricas de failover read-only | fixture |
| **matriz adversarial**: SIGKILL pós-`capacity_limited` reapropriável; evento duplicado idempotente; ledger truncado fail-closed; gate vermelho/domínio desconhecido não iniciam failover; seleção exige `adapter_enabled` | `test-provider-failover.sh` (Phase 8) |

## Regressão

| Check | Resultado |
|---|---|
| `scripts/check-shell.sh` | exit `0` |
| `scripts/check-doc-sync.sh` | exit `0` (VERSION `0.9.2`) |
| `scripts/ci-portable.sh` (23 testes) | exit `0` (inclui `test-provider-failover.sh`) |
| `scripts/test-ralph.sh` (loop legado) | 167 asserts verdes |
| `scripts/test-opencode-adapter.sh`, `test-agy-adapter.sh` | verdes (v1/v1.1 preservados) |
| `scripts/test-ralph-method.sh` | verde (crash/recovery) |

## Limitações e itens ainda não comprovados

- **Campo (Phase 9)**: a transição de failover Codex→OpenCode foi **comprovada em
  campo real** no `refactor-radar` (clone descartável isolado): shim codex
  injetou `usage_limited` → `provider.capacity_limited` → `continuation.generated`
  → `provider.failover_started` → **OpenCode real continuou a feature**, `bin/check`
  real verde, impl+verify completados, gates `validation` e `quality` aprovados.
  O gate `runtime_evidence` rejeitou porque a feature de prova
  (`expect(true)->toBeTrue()`) não exercita runtime real — defeito da feature de
  prova, não do failover. Os 5 gates completos foram exercitados no fluxo normal
  do `refactor-radar` (fase 29): **5/5 verdes** em campo (feature.released em
  2026-08-16 07:14:20Z), cobrindo o que a feature artificial não exercitava.
- a **normativa opencode completa** (5 gates aprovados pós-failover) exige o
  proof read-only real do OpenCode e o `bin/check` do projeto-alvo — comprovado
  em campo na fase 29 (validation, quality, runtime_evidence, technical_review e
  curation verdes);
- **matriz de panes exaustiva** (SIGTERM em todos os limites, ledger truncado
  em todos os pontos, fila longa multi-feature) ainda não é exaustiva;
- **promoção pendente**: STATUS/AGENT_GUIDE/roadmap/changelog/versão ainda não
  declaram o failover como entregue; isso ocorre no fluxo de promoção pelo Ralph
  (Phase 9, task 7).

## Revisão adversarial independente (Phase 8, task 5)

Revisão refute-first com agente independente, rodando os artefatos literais
(validador jsonschema, testes, ledger real de campo, CI portátil). Veredito:
**sem finding crítico/alto** — as 8 claims verificadas (schema v2 sem quebrar
v1/v1.1, loop devolve o rate limit sem dormir/relançar, cadeia de eventos de
failover, drift da policy bloqueia claim, circuitos só do ledger, CI verde,
sanitização sem vazamento, campo + 5/5 gates) se sustentaram com evidência de
execução real.

## Decisões de desenho desta candidata

- cadeia v1 limitada a `codex → opencode`, motivo `provider_usage_limited`;
- o loop nativo publica `runner-result` v2 e o controlador é a única autoridade
  de transição (nunca o runner);
- a cápsula de continuidade é projeção regenerável; o ledger permanece a fonte
  de verdade;
- `RALPH_OPENCODE_RESULT_V2=1` habilita o contrato v2 no adapter opencode; v1
  continua o default da migração.

# Relatório 0029 — candidata da FEATURE-098 (adapter Cursor)

**Versão candidata:** sobre a base `0.9.2` + commit `3332324`
**Commit de referência:** `3332324` (`feat(cursor)`)
**Data:** 2026-08-16
**Status:** candidata — fixture offline **verde**; campo opt-in e revisão
adversarial independente **pendentes** antes da promoção.

## Resultado

A FEATURE-098 torna o Cursor (CLI `agent`/`cursor-agent`) o terceiro adapter
executável do Ralph Method, no mesmo rito do `agy` (ADR + PRD + schema +
adapter na seam + fixtures offline). O Cursor é uma IDE com LLM embutido e sem
API key: a autenticação é a sessão local da conta, e o detector do
`ralph-init` não procura `CURSOR_API_KEY`. O contrato `runner-result 1.2.0`
tem terminal `result` e verify v1 **declarado** (`--mode ask`,
`permission_policy_status=declared`, hash `null`, agente `ask`) — `verified` é
proibido nesta versão.

## Fixture comprovada (offline, sem rede/credenciais/geração real)

| Capacidade | Prova |
|---|---|
| schema `1.2.0`: runner const `cursor`, campos v2 null, terminal `result`, `declared` no enum; v1/v1.1/v2 preservados | jsonschema (regressão dos 4 contratos) |
| `ralph-control` aceita `1.2.0+cursor`, verify declarado (hash null/agent ask) e rejeita `verified` para cursor | validação PHP + fixture |
| `ralph-init` detecta `agent`/`cursor-agent`, autentica por `status --format json` (sessão local) e exige `RALPH_CURSOR_MODEL` | `test-provider-readiness.sh` |
| `scripts/ralph.sh --engine cursor`: seam de adapters, preflight, fingerprint e modelo de verify | `check-shell.sh` + fixture |
| adapter `preflight|run|version`: impl completed, verify declarado, modelo observado | `test-cursor-adapter.sh` (CLI `agent` fake no PATH) |
| parser fail-closed: JSONL inválido, zero eventos, múltiplos `result`, escrita em verify, modelo divergente | `test-cursor-adapter.sh` |
| sanitização: eventos persistidos sem conteúdo completo do prompt/resposta | `test-cursor-adapter.sh` |

## Regressão

| Check | Resultado |
|---|---|
| `scripts/check-shell.sh` | exit `0` |
| `scripts/check-doc-sync.sh` | exit `0` (VERSION `0.9.2`) |
| `scripts/ci-portable.sh` (24 testes) | exit `0` (inclui `test-cursor-adapter.sh`) |
| `scripts/test-ralph.sh` (loop legado) | 167 asserts verdes |
| `scripts/test-provider-failover.sh` | verde (v2/execution-policy/failover intactos) |
| `scripts/test-installation.sh` | verde (ownership, apply/uninstall com perfil cursor) |
| `scripts/test-provider-readiness.sh` | verde (detecção/probe cursor) |
| `scripts/test-multiprovider.sh` | verde (seleção determinística com cursor na ordem) |

## Limitações e itens ainda não comprovados

- **campo opt-in**: o adapter não foi exercitado com a CLI Cursor real e uma
  sessão autenticada da IDE. A prova real de inferência é uma política futura,
  separada e opt-in — segue o mesmo rito do `agy` (`test-agy-field.sh` exige
  sessão local e não faz parte da CI sem credenciais);
- o **verify v1 declarado** (`--mode ask`) não é uma prova read-only com hash:
  `permission_policy_status=declared` registra a intenção, não uma verificação
  computada. A elevação para um modo verificado é decisão futura explícita,
  fora desta candidata;
- revisão **adversarial independente** não realizada (pendente, como na
  FEATURE-094/095);
- `docs/design/` (artefato do usuário) permanece fora do commit.

## Próxima etapa

Campo opt-in com sessão Cursor real, revisão adversarial independente sem
finding crítico/alto e, então, o fluxo de promoção do Ralph (VERSION + docs +
tag). O handoff de retorno ao `cursor-ralph-profile` é `HND-2026-00XX`
(conclusão da FEATURE-098).

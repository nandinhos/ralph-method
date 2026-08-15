# PLAN — Adapter nativo `agy`

## Objetivo

Entregar `agy` como runner executável e instalável, com implementação headless,
verify isolado, resultado normalizado e regressão completa, sem antecipar o
failover de `FEATURE-094`.

## Estratégia

1. registrar a evolução arquitetural e a seam comum de adapters;
2. congelar fixtures reais sanitizadas do JSONL `agy 1.1.13`;
3. implementar parser/política/runner fail-closed;
4. integrar readiness, instalação e loop pela seam;
5. comprovar com fixtures offline, isolamento e campo real;
6. sincronizar documentação somente com evidência verde.

## Decisões vinculantes

- identificador canônico: `agy`;
- adapter: `adapters/agy/`;
- resultado `agy`: `schema_version=1.1.0`, terminal `result`;
- OpenCode mantém `schema_version=1.0.0` e terminal `step_finish`;
- verify v1: Linux + `bwrap` allowlisted; `plan` não é boundary;
- contrato do loop para adapters: `preflight|run|version` + resultado comum;
- fallback: `none`; o importador de `bin/ralph-control` aceita `agy` 1.1 sem
  alterar máquina de estados, gates, leases ou fencing.

## Ordem e dependências

```text
Arquitetura
  → contratos/fixtures
  → adapter
  → seam do loop/readiness/instalação
  → testes offline
  → campo/adversarial
  → documentação final
```

## Evidência mínima

- `bash -n` e `php -l` nos arquivos novos/alterados;
- testes `test-agy-policy`, `test-agy-adapter`, readiness, instalação,
  multiprovider e loop;
- todos os checks obrigatórios de `AGENTS.md`;
- smoke real sanitizado de impl e verify com `agy 1.1.13`;
- revisão adversarial sem finding crítico/alto aberto.

## Não objetivos

- generalizar runners nativos Codex/Claude;
- implementar outcome/failure domain/failover v2;
- suportar verify em macOS/Windows;
- mudar ledger, gates, leases ou fencing.

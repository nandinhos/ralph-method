# Plano de promoção do ledger para `RALPH_SCHEMA_VERSION=1.2.0`

- **Estado:** planejado (Phase 1 da FEATURE-094); nenhum evento `1.2.0` é emitido.
- **Referência:** [`provider-failover-continuity-plan.md`](provider-failover-continuity-plan.md) §9.
- **Decisão:** [`ADR-0016`](../adr/0016-failover-controlado-entre-providers.md).

## Objetivo

Emitir os cinco eventos novos da continuidade
(`provider.capacity_limited`, `continuation.generated`,
`provider.failover_started`, `provider.capacity_wait_started`,
`provider.capacity_wait_finished`) somente quando o leitor compatível estiver
instalado, sem quebrar ledgers históricos `1.0.0` e `1.1.0`.

## Regras de compatibilidade

- **Unidirecional:** o binário novo lê `1.0.0` e `1.1.0`; o binário novo ainda
  não grava `1.2.0` (nesta fase). Binários antigos rejeitam qualquer evento
  com schema não suportado, por segurança (fail-closed).
- **Leitor antes de writer:** `RALPH_COMPATIBLE_SCHEMA_VERSIONS` e a lista
  `$eventTypes` de `bin/ralph-control` são promovidos **antes** do primeiro
  `appendEvent` com schema `1.2.0`.
- **Tipo desconhecido nunca é tolerado silenciosamente:** `validateEventShape`
  falha com schema fora da lista compatível; a projeção não avança uma
  transição de autoridade com evento que não entende.

## Sequência de promoção (fases posteriores da FEATURE-094)

1. `RALPH_SCHEMA_VERSION` passa a `1.2.0` e
   `RALPH_COMPATIBLE_SCHEMA_VERSIONS` inclui `1.2.0`, mantendo `1.0.0`/`1.1.0`.
2. A lista `$eventTypes` ganha os cinco tipos novos **no mesmo commit** do
   leitor — nunca em writer isolado.
3. O primeiro `appendEvent` com schema `1.2.0` só acontece após o commit acima
   instalado (Phase 4 da FEATURE-094, `provider.capacity_limited`).
4. A regressão `scripts/test-provider-failover.sh` cobre o fail-closed de
   binário antigo: um evento `1.2.0` anexado ao ledger é rejeitado antes de
   qualquer transição (seção "Compatibilidade do ledger").

## Prova atual (Phase 1)

O teste `scripts/test-provider-failover.sh` comprova nesta fase:

- o binário novo aceita o manifest `1.0.0` e lê o ledger `1.1.0`;
- um evento com `schema_version=1.2.0` é rejeitado por `validateEventShape`
  (fail-closed sem leitor compatível).

O `bin/ralph-control` permanece em `RALPH_SCHEMA_VERSION=1.1.0` e
`RALPH_COMPATIBLE_SCHEMA_VERSIONS=['1.0.0','1.1.0']` até a Phase 4.

## Não é escopo

- Emitir eventos `1.2.0` nesta fase;
- tolerar tipo desconhecido;
- migrar ledgers existentes para outro schema.

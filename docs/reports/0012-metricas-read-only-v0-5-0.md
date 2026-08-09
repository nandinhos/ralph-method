# Relatório 0012 — métricas read-only da candidata v0.5.0

**Data:** 2026-08-09
**Versão:** `0.5.0`
**Commit de implementação:** `784fb24`
**Branch:** `feat/ralph-hardening`
**Escopo:** agregação histórica sem mutação do control plane

## Contrato entregue

`bin/ralph-metrics` lê `.git/ralph-control/events.jsonl` e escreve JSON ou
Markdown em stdout. Os filtros `--workflow` e `--feature` reduzem o contexto
sem editar o ledger. O componente calcula somente fatos derivados:

- eventos por tipo;
- workflows, features e tentativas;
- comandos aprovados e falhos;
- gates aprovados e rejeitados;
- recuperações exigidas e resolvidas;
- candidatos, curadorias, rejeições e revisões de conhecimento;
- duração observada entre `attempt.started` e `block.finished`;
- duração observada de recuperação.

Não há persistência implícita, escrita de relatório, reparo de ledger,
transição de estado, decisão de gate, estimativa de token ou métrica de custo.

## Cenários comprovados

| Cenário | Resultado |
|---|---|
| Ledger com dois workflows/features e três tentativas | agregado corretamente |
| Filtro por feature | reduz eventos e features ao contexto solicitado |
| Saída JSON | schema de métricas e contagens presentes |
| Saída Markdown | tabela de resumo e features presente |
| Duração de tentativa | calculada para tentativas concluídas |
| Duração de recuperação | calculada entre exigência e resolução |
| Ledger corrompido | rejeitado com exit code `3` |
| Imutabilidade | hash do `events.jsonl` não mudou |
| Instalação | `ralph-metrics` entra no manifesto e no uninstall por ownership |
| Reprodução | bundle Git instala o componente em projeto independente |

## Evidência

```bash
bash scripts/ci-portable.sh
```

Resultado final do checkpoint:

```text
OK: bundle Git reproduzido em projeto independente; plan/apply/doctor/uninstall e limpeza passaram.
OK: métricas read-only, agregação, duração, filtros, Markdown e ledger corrompido passaram.
TODOS VERDES: 163 asserts
OK: CI portátil concluída sem credenciais ou geração real.
```

## Decisão e limites

A Fase 4 está concluída nesta branch. A funcionalidade é propositalmente
enxuta e não substitui `ralph-monitor`, `ralph-trace` ou o `ralph-control`.
Ela também não é `ralph-observability` de custos: qualquer futura medição de
uso, orçamento ou provider deve ser uma decisão separada.

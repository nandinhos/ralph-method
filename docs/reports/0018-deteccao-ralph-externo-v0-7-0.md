# Relatório 0018 — Detecção segura de Ralph externo (`v0.7.0`)

## Estado

Validado na branch `dev`, sem promoção para `main` e sem tag da v0.7.0.

## Objetivo

Verificar se o projeto-alvo já contém uma instalação Ralph que não pertence ao
Ralph Method antes de permitir um `apply`. A barreira deve informar o agente
sem expor conteúdo e impedir sobrescrita silenciosa.

## Implementação comprovada

| Área | Evidência | Resultado |
|---|---|---|
| Contrato | `schemas/ralph-installation-detection.schema.json` | JSON válido, versão `1.0.0` |
| Detecção | `bin/ralph-init` → `ralph_installation` | método gerenciado, não instalado, externo ou inválido diferenciados |
| Sanitização | sinais com caminho relativo, tipo e SHA-256 | conteúdo, prompt, token e credencial não entram na saída |
| Bloqueio | `apply` após `plan` e revalidação pós-lock | origem `detected`, `ambiguous` ou `invalid` bloqueia com exit `3` |
| Preservação | fixture com `ralph.sh` e `Ralphfile` | arquivos legados permanecem intactos |
| Coexistência | fixture com Ralph Method válido + marcador externo | marcador posterior também bloqueia |
| Caso neutro | pasta `.ralph` sem marcador conhecido | não bloqueia por si só |
| Diagnóstico | `doctor` | reporta `external_ralph_detected` ou `invalid_installation` |
| Reprodução | `scripts/test-reproducibility.sh` | bundle independente instala, verifica e remove sem regressão |

## Checks executados

| Comando | Resultado |
|---|---|
| `php -l bin/ralph-init` | exit `0` |
| `bash scripts/check-doc-sync.sh` | verde com `VERSION=0.7.0` |
| validação JSON do schema | exit `0` |
| `bash scripts/test-installation.sh` | verde: instalação, idempotência, ownership, detecção, bloqueio e preservação |
| `bash scripts/test-reproducibility.sh` | verde: bundle Git independente |
| `bash scripts/ci-portable.sh` | verde; loop registrou `163 asserts` |
| `git diff --check` | sem erro de whitespace |

## Decisão operacional

O `apply` comum não move a instalação encontrada. O agente deve preservar os
arquivos, apresentar os sinais e iniciar uma revisão de evolução. Não existe
importação automática de `.git/ralph-control`, workflow, prompts, credenciais
ou eventos externos.

## Limitação conhecida

A operação assistida de evolução com backup verificável, isolamento,
instalação transacional, manifesto de rollback e restauração condicional ainda
é uma próxima fase. Ela está descrita em
[`docs/adr/0010-deteccao-evolucao-de-ralph-externo.md`](../adr/0010-deteccao-evolucao-de-ralph-externo.md)
e no roadmap, mas não deve ser simulada por um `apply` normal.

## Origem

- implementação: `bin/ralph-init`;
- fixtures: `scripts/test-installation.sh`;
- contrato: `schemas/ralph-installation-detection.schema.json`;
- decisão: ADR-0010;
- versão em desenvolvimento: `VERSION` (`0.7.0`).

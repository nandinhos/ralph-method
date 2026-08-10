# Relatório 0019 — Validação da evolução assistida no OpenCode (`v0.8.0`)

## Estado

Validado na branch `dev`, com a promoção para `main` condicionada aos checks
finais e ao commit desta evolução.

## Objetivo

Comprovar, em um projeto isolado e controlado pelo próprio OpenCode, o ciclo de
evolução de uma instalação Ralph externa sem importar estado desconhecido:

```text
plan → apply → awaiting_acceptance → rollback → restored
```

A prova deveria demonstrar backup numerado, isolamento dos sinais legados,
instalação idempotente, rollback com hashes e preservação do projeto original.

## Ambiente de campo

| Item | Valor |
|---|---|
| Ralph Method | `0.8.0` |
| Harness | OpenCode |
| Versão do OpenCode | `1.18.15` |
| Modelo informado pelo runner | `opencode/deepseek-v4-flash-free` |
| Projeto | fixture Git temporária, fora deste checkout |
| Identificador da evolução | `EVL-20260810-0001` |
| Modo | `quarantine_only` |

O projeto de campo continha somente os sinais legados controlados `ralph.sh` e
`Ralphfile`, com conteúdo sintético. Nenhum prompt, credencial, evento,
workflow ou ledger externo foi lido ou migrado.

## Resultado por etapa

| Etapa | Expectativa | Resultado observado | Status |
|---|---|---|---|
| `evolve --plan` | detectar Ralph externo e exigir operação explícita | plano pronto, `quarantine_only`, sem importação de estado e com dois sinais | verde |
| `evolve --apply` | isolar sinais e instalar a versão nova | `EVL-20260810-0001`, estado `awaiting_acceptance`, manifesto e backup presentes | verde |
| repetição do apply | não duplicar evolução nem backup | retornou `already_pending` com o mesmo identificador | verde |
| `rollback --plan` | liberar rollback somente sem drift | plano pronto e permitido | verde |
| `rollback --apply` | restaurar legado e remover instalação nova | estado `rolled_back`, `ralph.sh` e `Ralphfile` restaurados | verde |
| verificação independente | confirmar integridade fora da saída do agente | hashes restaurados, raiz compatível, manifesto ausente e estágio removido | verde |

O marcador emitido durante a execução foi:

```text
RALPH_EVOLUTION_CHECK_OK evolution_id=EVL-20260810-0001 status_final=rolled_back checks=6
```

## Evidência independente

Depois da execução do OpenCode, a verificação externa ao agente confirmou:

- `state_status=rolled_back`;
- raiz persistida igual à raiz do projeto de campo;
- manifesto novo ausente;
- diretório de estágio de rollback ausente;
- hashes de `ralph.sh` e `Ralphfile` iguais aos originais;
- arquivos de backup removidos após restauração concluída;
- nenhum arquivo novo do Ralph Method no projeto de origem;
- único artefato operacional remanescente: `.ralph/install.lock`.

O lock remanescente é um artefato operacional esperado do método e não contém
estado de produto, credencial ou conteúdo legado.

## Checks locais complementares

| Comando | Resultado |
|---|---|
| `php -l bin/ralph-init` | exit `0` |
| `bash scripts/test-installation.sh` | verde: instalação, evolução, idempotência, drift, recuperação e rollback |
| `bash scripts/check-shell.sh` | 25 scripts aprovados por `bash -n` e `shellcheck` |
| `git diff --check` | sem erro de whitespace |
| `bash scripts/ci-portable.sh` | verde; `test-ralph.sh` registrou `163 asserts` |

## Decisão

A evolução `v0.8.0` está comprovada para o contrato atual: detectar,
quarentenar, instalar, aguardar aceite e permitir rollback condicional por
hash. Ela é segura para ser promovida para `main` e testada em um projeto real
com OpenCode.

O aceite permanece explícito. A operação não promove automaticamente uma
instalação externa, não faz importação semântica e não transforma o hook em
autoridade de estado.

## Limitações e próximos hardenings

Ainda não foi simulado um `SIGKILL` real durante um `rename` nem falta real de
espaço no filesystem. A recuperação determinística de um estado interrompido,
com reconstrução a partir do manifesto e preservação do estágio, foi coberta
pela suíte portátil. Adapters de migração semântica continuam fora do escopo
até existir um contrato específico por origem.

## Origem

- implementação: [`bin/ralph-init`](../../bin/ralph-init);
- contrato: [`schemas/ralph-evolution.schema.json`](../../schemas/ralph-evolution.schema.json);
- regressão: [`scripts/test-installation.sh`](../../scripts/test-installation.sh);
- decisão: [`ADR-0011`](../adr/0011-evolucao-assistida-backup-rollback.md);
- validação anterior de detecção: [`Relatório 0018`](0018-deteccao-ralph-externo-v0-7-0.md).

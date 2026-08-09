# Incidente 0010 — CI portátil com PHP 8.2

**Data:** 2026-08-09
**Componente:** CI portátil, prontidão de providers e control plane
**Run afetado:** [GitHub Actions 31339614180](https://github.com/nandinhos/ralph-method/actions/runs/31339614180)
**Commit afetado:** `5d579b5`
**Status:** hotfix validado localmente; CI remoto pendente

## Sintoma

O push da promoção da `v0.6.0` iniciou o workflow `CI portátil do Ralph
Method`. O job `Checks portáteis` falhou em
`scripts/test-provider-readiness.sh` com `FALHA: assertiva JSON falhou`.

## Impacto

`main` e a tag `v0.6.0` foram publicados, mas a validação remota ficou
vermelha. Nenhum novo ajuste foi enviado para `main` depois da falha. A
correção foi isolada na branch `fix/ci-portable-path` para pré-teste.

## Causa raiz

Foram encontradas duas incompatibilidades independentes:

1. Os fixtures sobrescreviam o `PATH` com `fake_bin:/usr/bin:/bin`. Em
   runners que instalam PHP pelo toolcache, isso podia ocultar o PHP efetivo.
2. No PHP 8.2, consultar `proc_get_status()` antes de `proc_close()` pode fazer
   `proc_close()` retornar `-1`, mesmo quando o processo terminou com exit code
   `0` ou `1`. O `ralph-init` e o `ralph-control` usavam o valor de
   `proc_close()` como autoridade do resultado.

## Correção aplicada

- os testes provider, multiprovider e OpenCode preservam o diretório real do
  PHP e apenas prefixam os binários fixture;
- o cenário `no_runner` preserva o PHP, mas continua removendo os providers de
  fixture;
- `bin/ralph-init` preserva o `exitcode` observado antes de fechar o processo;
- `bin/ralph-control` aplica a mesma regra em debugging read-only, execução
  controlada e supervisão;
- o fechamento continua ocorrendo para liberar recursos, mas não substitui
  um exit code válido já observado.

## Evidência local

| Verificação | Resultado |
|---|---|
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/test-provider-readiness.sh` | exit `0` |
| PHP 8.2: provider, multiprovider e OpenCode | exit `0` |
| `bash scripts/ci-portable.sh` local | exit `0` |
| Suíte do Ralph Method | 163 asserts verdes |
| `git diff --check` | exit `0` |

O container PHP 8.2 não foi usado como substituto do GitHub Actions para a
suíte completa: o Docker local bloqueia `unshare` por permissão do namespace.
Esse limite foi separado das falhas de código e o caminho sem namespace foi
validado nos testes relevantes.

## Prevenção

O hotfix será enviado primeiro para uma branch de pré-teste. A promoção para
`main` só será considerada novamente depois de um novo run remoto verde.

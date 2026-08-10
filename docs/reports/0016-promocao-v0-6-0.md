# Relatório 0016 — promoção da v0.6.0

**Versão:** `0.6.0`
**Commit promovido:** `5d579b5`
**Branch de destino:** `main`
**Tag:** `v0.6.0` anotada
**Data:** 2026-08-09
**Status:** publicada em `origin/main`, com CI pós-publicação em correção

## Resultado

A evolução de memória episódica, retenção seletiva e taxonomia foi integrada
em `main` por fast-forward, sem merge commit artificial. A tag anotada
`v0.6.0` aponta para o mesmo commit promovido e foi publicada no repositório
remoto:

```text
https://github.com/nandinhos/ralph-method.git
```

## Pré-condições verificadas

| Verificação | Resultado |
|---|---|
| Árvore local antes da promoção | limpa |
| `main` remoto antes da promoção | `6dd9b29` |
| Candidata | `feat/ralph-hardening`, 12 commits à frente |
| Integração | `git merge --ff-only` concluído |
| Portão final | `bash scripts/ci-portable.sh` exit `0` |
| Suíte do loop | 163 asserts verdes |
| Documentação, shell e schemas | verdes |
| Instalação, desinstalação e reprodução | verdes |
| Providers, multiprovider, knowledge, metrics e OpenCode | verdes |

## Verificação pós-publicação

O primeiro workflow remoto da promoção falhou em
`scripts/test-provider-readiness.sh` no run
[31339614180](https://github.com/nandinhos/ralph-method/actions/runs/31339614180).
O diagnóstico encontrou uma composição de `PATH` não portátil nos fixtures e
uma diferença real do PHP 8.2: depois de `proc_get_status()`, `proc_close()`
pode retornar `-1` mesmo com exit code válido. A correção foi isolada na
branch `fix/ci-portable-path` e ainda não foi promovida para `main`.

O postmortem completo está em
[`docs/incidents/0010-ci-php82-process-status.md`](../incidents/0010-ci-php82-process-status.md).

## Limites registrados

A revisão adversarial independente da última evolução foi iniciada, mas
excedeu o timeout e foi encerrada sem veredicto estruturado. Essa tentativa
não foi contada como aprovação. A promoção se baseia na regressão portátil
reproduzível e nos checks documentados; o limite permanece explícito para
revisão futura.

Busca semântica, hub externo e grafo de relações continuam fora da versão
publicada e permanecem no roadmap. Hermes e agy continuam no backlog sem
prioridade.

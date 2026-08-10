# Relatório 0017 — release de manutenção v0.6.1

**Versão:** `0.6.1`
**Base promovida:** merge `ba98dfa`
**Branch de destino:** `main`
**Tag:** `v0.6.1` anotada
**Data:** 2026-08-09
**Status:** pronta para reprodução em projeto independente

## Objetivo

Fechar a validação pós-promoção da v0.6.0, corrigir incompatibilidades
observadas no runner PHP 8.2 do GitHub Actions e deixar a documentação
operacional coerente com o estado publicado.

## Correções consolidadas

| Área | Correção | Evidência |
|---|---|---|
| Fixtures | PATH preserva o PHP efetivo e isola somente os binários falsos | `scripts/test-provider-readiness.sh`, `scripts/test-multiprovider.sh` e `scripts/test-opencode-adapter.sh` |
| Processos PHP 8.2 | exit code observado antes de `proc_close()` é preservado | `bin/ralph-init` e `bin/ralph-control` |
| Ferramentas do runner | `test-ralph-method.sh` usa `grep -Eq` quando `rg` não existe | `scripts/test-ralph-method.sh` |
| Supervisão | capacidade real de `unshare` é sondada antes de selecionar o isolamento | `bin/ralph-control` |
| Instalação | o manifesto instalado acompanha `VERSION` e o guia em `0.6.1` | `bin/ralph-init` |
| Documentação | status, guia, README, changelog e incidente do CI pós-promoção sincronizados | este relatório e `scripts/check-doc-sync.sh` |

## Gates de validação

| Verificação | Resultado |
|---|---|
| `bash scripts/check-doc-sync.sh` | exit `0` |
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/ci-portable.sh` local | exit `0`; 163 asserts verdes |
| Reprodução em PHP 8.2 Docker | exit `0`; regressão completa verde |
| CI remoto após o hotfix | run `31341326999` verde |
| GitGuardian | verde no PR #1 |
| Checkout após promoção | `main...origin/main`, árvore limpa |

O `Killed` exibido durante o smoke test é o encerramento proposital do fixture
de crash; o teste captura esse cenário e termina com todos os asserts verdes.

## Prontidão para outro projeto

O método permanece desacoplado do `refactor-radar`, com instalação exclusiva
por projeto, `plan/apply/uninstall`, doctor, ownership por hash, feedback para
orquestrador externo, readiness condicional e reprodução a partir de bundle
Git limpo. Para um projeto novo, o caminho recomendado é:

```bash
ralph-init plan --project /caminho/do/projeto
ralph-init apply --project /caminho/do/projeto --provider auto --verify-providers
ralph-doctor --project /caminho/do/projeto
```

Hermes e agy continuam fora do escopo executável, no backlog sem prioridade.
Busca semântica, hub externo e grafo de relações continuam adiados até que a
taxonomia e os índices atuais demonstrem uma limitação real.

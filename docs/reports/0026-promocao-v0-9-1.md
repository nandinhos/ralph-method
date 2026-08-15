# Relatório 0026 — promoção da v0.9.1

**Versão:** `0.9.1`
**Commit promovido:** `daa5a98` (HEAD da `main`)
**Branch de destino:** `main`
**Tag:** `v0.9.1` anotada
**Data:** 2026-08-15
**Status:** publicada em `origin/main`

## Resultado

A `v0.9.1` publica a **FEATURE-096** — o comando de gate como contrato nativo
do método — sobre a base `0.9.0`. A integração foi feita por
`git merge --ff-only`/push direto em `main`, e a tag anotada `v0.9.1` aponta
para o commit `daa5a98`, publicada em `origin/main`.

## Pré-condições verificadas

| Verificação | Resultado |
|---|---|
| Árvore local antes da promoção | limpa |
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/check-doc-sync.sh` | exit `0` (VERSION `0.9.1`) |
| `bash scripts/ci-portable.sh` | exit `0`; inclui `test-ralph-gates-native.sh` verde |
| Revisão adversarial da FEATURE-096 | 3 findings corrigidos e revalidados; sem finding aberto |

## FEATURE-096 — gates como contrato nativo

- **Contrato de contexto por env**: o supervisor fornece ao comando de gate
  `RALPH_WORKFLOW_ID`, `RALPH_FEATURE_KEY`, `RALPH_ATTEMPT`, `RALPH_GATE` e
  `RALPH_REPORT_PATH` (sem argumentos posicionais); o lease não é exportado.
- **Wrappers canônicos**: `ralph-run-quality.sh`, `ralph-run-runtime-evidence.sh`
  e `ralph-run-independent-gate.sh` leem o contrato por env; no modo supervisor
  (presença de `RALPH_GATE`) só emitem evidência + exit code; no modo manual
  (com `--lease`) registram o gate como antes.
- **Defaults nativos**: `runtime_evidence` (env → `scripts/*runtime-evidence*`
  excluindo `ralph-run-*` → `bin/check`), `technical_review` (env; sem comando,
  rejeita sem inventar revisão) e `curation` (env →
  `bin/ralph-knowledge --workflow --feature`); o `supervise` executa os cinco
  gates numa instalação padrão sem retornar `gates_configuration_required`.
- **Refinamentos pós-adversarial**: detecção de runtime não recursa no próprio
  wrapper; modo manual preservado; higiene de ambiente (lease fora do comando);
  `quality` com diagnóstico limpo quando `bin/check` ausente.

## Revisão adversarial

A revisão independente encontrou 3 findings no candidato e todos foram
corrigidos e revalidados antes da promoção:

1. **high — recursão no default de `runtime_evidence`**: a detecção
   `scripts/*runtime-evidence*` casava com o próprio wrapper instalado,
   re-executando-o em loop. Correção: excluir `ralph-run-*` da detecção.
2. **medium — modo manual quebrado**: `SUPERVISOR` era sempre 1 por causa do
   default de `GATE`. Correção: supervisor só ativa com `RALPH_GATE` presente;
   chamada manual com `--lease` registra o gate.
3. **medium — higiene de ambiente**: o lease e o env completo do supervisor
   vazavam para o comando de gate. Correção: `RALPH_LEASE` não é exportado e
   `putenv` neutraliza env pré-existente.

A revalidação confirmou os 3 fechamentos com evidência de código e execução
real, sem finding remanescente.

## Limites registrados

- A FEATURE-097 (recuperação de gate distinta entre defeito do comando e falha
  da feature) está registrada no roadmap como prioridade alta, com handoff
  `HND-2026-0008`, e será implementada após esta promoção.
- A prova real de campo do detector legado com o projeto-alvo original
  permanece adiada (validação por fixture versionada).

## Verificação pós-publicação

Após a promoção, o checkout foi verificado com árvore limpa e
`main...origin/main` sincronizado. O guia foi sincronizado para
`method_version: 0.9.1` no mesmo commit, conforme a regra de `check-doc-sync`.

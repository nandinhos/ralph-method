# Relatório 0025 — promoção da v0.9.0

**Versão:** `0.9.0`
**Commit promovido:** `HEAD` da branch `feat/detector-bc-legacy`
**Branch de destino:** `main`
**Tag:** `v0.9.0` anotada
**Data:** 2026-08-14
**Status:** publicada em `origin/main`

## Resultado

A `0.9.0` consolida em `main` duas entregas da branch
`feat/detector-bc-legacy`: o detector legado `bc-harness` (features
`091-DETECT-BC-LEGACY`, `092-EVOLVE-BC-LEGACY` e `093-REGRESSION-RELEASE`) e o
adapter nativo `agy` (FEATURE-095). A integração foi feita por
`git merge --ff-only`, sem merge commit artificial, e a tag anotada `v0.9.0`
aponta para o commit promovido, publicada em `origin/main`.

## Pré-condições verificadas

| Verificação | Resultado |
|---|---|
| Árvore local antes da promoção | limpa |
| `main` remoto antes da promoção | `24fe863` |
| Candidata | `feat/detector-bc-legacy`, 26 commits à frente |
| Integração | `git merge --ff-only` concluído |
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/check-doc-sync.sh` | exit `0` (VERSION `0.9.0`) |
| `bash scripts/ci-portable.sh` | exit `0`; 163 asserts verdes; checks agy verdes |
| `test-agy-adapter.sh`, `test-agy-loop.sh`, `test-agy-control.sh` | verdes |
| `test-provider-readiness.sh`, `test-multiprovider.sh`, `test-installation.sh` | verdes |
| Prova real de campo | `test-agy-field.sh` verde com `agy 1.1.13` |
| Revisão adversarial | dois findings corrigidos e revalidados; nenhum finding aberto |

## Revisão adversarial

A revisão independente encontrou dois findings no candidato original e ambos
foram corrigidos antes da promoção:

- **high — preflight verify dependia de `agy agents`**: a listagem global expõe
  somente agentes instalados da sessão local e nunca o agente do workspace; o
  preflight falhava com exit `2` no campo real. Correção: o preflight comprova
  `ralph-review` pela presença de `.agents/agents/ralph-review/agent.md` no
  `repo-root` (fonte que o `run` consome via `--add-dir`), e o readiness usa
  `agy agents` apenas como prova de CLI funcional.
- **medium — parser aceitava evento pré-init de outra conversa**: um
  `step_update` de outra conversa antes do `init` era projetado e o resultado
  terminava `completed`. Correção: o parser rejeita `step_update`/`result`
  anterior ao primeiro `init` (`stream deve iniciar com init`), com fixture de
  regressão `pre_init_other`.

A revalidação adversarial independente confirmou ambos os fechamentos com
evidência real e sem finding remanescente.

## Limites registrados

- verify v1 do `agy` permanece restrito ao Linux com `bwrap` allowlisted;
- `FEATURE-094` (failover) e `fallback_policy=none` permanecem inalterados;
- a prova real de campo do detector legado com o projeto-alvo original
  (`teste-events-opencode`) permanece adiada; a validação usa fixture
  versionada, conforme registrado nos relatórios `0021` e `0023`.

## Verificação pós-publicação

Após a promoção, o checkout foi verificado com árvore limpa e
`main...origin/main` sincronizado. O guia de agentes foi sincronizado para
`method_version: 0.9.0` no mesmo commit, conforme a regra de `check-doc-sync`.

# Relatório 0027 — promoção da v0.9.2

**Versão:** `0.9.2`
**Commit promovido:** `6b42689` (HEAD da `main`)
**Branch de destino:** `main`
**Tag:** `v0.9.2` anotada
**Data:** 2026-08-15
**Status:** publicada em `origin/main`

## Resultado

A `v0.9.2` publica a **FEATURE-097** — recuperação de gate distinta entre
defeito do comando e falha da feature — sobre a base `0.9.1`, além do teste de
resiliência a falha de filesystem na evolução assistida
(`test-evolution-filesystem.sh`). A correção foi **confirmada em campo** pelo
`refactor-radar` (INC-2026-0007): a phase-25 fechou com os 5 gates e o
workflow avançou para a phase-26 sem re-execução do bloco commitado. A tag
anotada `v0.9.2` aponta para o commit `6b42689`, publicada em `origin/main`.

## Pré-condições verificadas

| Verificação | Resultado |
|---|---|
| Árvore local antes da promoção | limpa |
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/check-doc-sync.sh` | exit `0` (VERSION `0.9.2`) |
| `bash scripts/ci-portable.sh` | exit `0`; inclui `test-ralph-gate-recovery.sh` (cenários A–D) verde |
| Confirmação de campo | `refactor-radar`: phase-25 fechada, workflow avançou (HND-2026-0011) |

## FEATURE-097 — recuperação de gate

- **Classificação**: `gate.passed`, `gate.rejected` (evidência mostra falha da
  feature → `debugging_required`) e `gate.harness_error` (comando sem evidência
  — stdout e stderr vazios — ou timeout → a feature permanece `awaiting_gates`);
- **Retry de gate sem re-execução do bloco**: após `debugging_verified` com
  bloco commitado e falha de gate, o supervisor usa `beginGateRetry`
  (`gate.retry_started` → `awaiting_gates`) e re-roda só o gate pendente;
- **Default de curation pré-release** read-only (`ralph-knowledge candidates`);
- **Self-test** `ralph-control gate-test --gate <gate>` com o `gate-timeout`
  do gate real (default 900s).

## Confirmação de campo (INC-2026-0007)

- método 0.9.1 aplicado no `refactor-radar`, drift preservado, doctor ok;
- phase-25: os cinco gates passaram → `feature.approved` →
  `feature.released` (2026-08-15T21:43:23Z) → `feature.advanced`;
- workflow avançou para a phase-26; árvore limpa;
- os 6 findings do HND-2026-0011 foram endereçados (default de curation,
  timeout do gate-test, retry re-executando bloco, exit espúrio, LLM sem
  evidência, executor instável).

## Resiliência a falha de filesystem (item do roadmap 0.8.0)

A v0.9.2 incorpora o `scripts/test-evolution-filesystem.sh`, que fecha o item
"testar SIGKILL real durante rename e espaço insuficiente com fixture de falha
de filesystem":

- **SIGKILL real durante o rename de publicação** (fase `installing`): o
  `evolve --apply` é interrompido no meio de `commitStagedFiles`; o rollback
  restaura a árvore legada (incluindo symlink interno e modos) sem deixar
  instalação nova;
- **falha de filesystem no destino** (diretório read-only, simulando espaço
  insuficiente): o `evolve` falha fechado, o estado vira `recovery_required` e
  o rollback restaura a árvore legada.

## Limites registrados

- A prova real de campo do detector legado com o projeto-alvo original
  permanece adiada (validação por fixture versionada);
- a integração semântica de memória e o grafo de relações permanecem no
  roadmap (sem gatilho mensurável);
- Hermes segue sem adapter, no backlog sem prioridade.

## Verificação pós-publicação

Após a promoção, o checkout foi verificado com árvore limpa e
`main...origin/main` sincronizado. O guia foi sincronizado para
`method_version: 0.9.2` no mesmo commit, conforme a regra de `check-doc-sync`.

# Relatório 0021 — Regressão e preparação de release do detector legado (`bc-harness`)

## Estado

Regressão concluída na branch `feat/detector-bc-legacy`. A promoção para `main`
permanece condicionada à revisão independente e ao commit único da fase, que
são de responsabilidade do `scripts/ralph.sh` e não desta sessão.

## Objetivo

Validar de forma determinística que a detecção e a evolução da instalação
Ralph legada `bc-harness` (features `091-DETECT-BC-LEGACY` e
`092-EVOLVE-BC-LEGACY`) não regrediram a instalação, a reprodutibilidade, o
feedback e os harnesses fechados, além de confirmar o bloqueio fail-closed do
`apply` comum e o ciclo completo de evolução em fixture isolada — sem executar
o projeto-alvo original onde o padrão legado foi observado em campo.

## Ambiente

| Item | Valor |
|---|---|
| Branch | `feat/detector-bc-legacy` (HEAD `de9e943`) |
| Ralph Method | `0.8.0` |
| PHP | `8.4.1` (cli) |
| Árvore de trabalho | limpa no início e ao final da fase |
| Projeto-alvo original | não executado; padrão reproduzido por fixture `tests/fixtures/bc-harness-legacy` |

## Resultado por etapa da fase

| # | Item da fase | Comando/confirmação | Resultado | Status |
|---|---|---|---|---|
| 1 | lint dos componentes alterados | `php -l` em `bin/ralph-control`, `bin/ralph-init`, `adapters/opencode/parser.php`, `adapters/opencode/policy.php` | `No syntax errors detected` em todos | verde |
| 2 | shell limpo | `bash scripts/check-shell.sh` | 27 arquivos `bash -n` + `shellcheck` OK | verde |
| 3 | doc sincronizada | `bash scripts/check-doc-sync.sh` | `OK: guia sincronizado com 0.8.0` | verde |
| 4 | instalação por projeto | `bash scripts/test-installation.sh` | `OK: instalação, idempotência, ownership, desinstalação e preservação passaram.` | verde |
| 5 | reprodutibilidade | `bash scripts/test-reproducibility.sh` | `OK: bundle Git reproduzido em projeto independente; ...` | verde |
| 6 | regressão multiprovider e OpenCode | `bash scripts/test-multiprovider.sh`, `bash scripts/test-opencode-policy.sh`, `bash scripts/test-opencode-adapter.sh` | verdes | verde |
| 7 | CI portátil | `bash scripts/ci-portable.sh` | 14 checks verdes + `OK: CI portátil concluída` | verde |
| 8 | instalação neutra permitida | plano em projeto com `.ralph/` sem marcador | `status=not_found`, `apply_allowed=true`, `apply` exit `0` | verde |
| 9 | `harness/ralph/` bloqueia apply comum | plano em fixture `bc-harness-legacy` | `detected`, `external_ralph_legacy`, `family=bc-harness`, `legacy_type=legacy_directory`, `apply_allowed=false`, `apply` exit `3` | verde |
| 10 | evolve / aceite / drift / rollback em fixture | ciclo em fixture isolada | ver seção própria | verde |
| 11 | relatório numerado | este documento | `0021` | verde |
| 12 | docs de release atualizadas | ADR, STATUS, roadmap, changelog, guia | ver seção própria | verde |
| 13 | limitações registradas | sem executar o projeto-alvo original | ver seção própria | verde |
| 14 | commit e promoção | não criados nesta sessão | guardado para a revisão independente e o `ralph.sh` | condicionado |

## Confirmações diretas (fixture isolada)

Executadas fora da suíte, para evidência independente:

1. **Instalação neutra continua permitida**: projeto com `.ralph/project-notes.txt`
   (sem marcador conhecido) → `ralph_installation.external.status=not_found`,
   `apply_allowed=true`, `apply` com exit code `0` e instalação publicada.

2. **`harness/ralph/` bloqueia o apply comum**: fixture
   `tests/fixtures/bc-harness-legacy/harness/ralph` → `status=detected`,
   `classification=external_ralph_legacy`, `family=bc-harness`,
   `legacy_type=legacy_directory`, `recommended_action=evolve`,
   `apply_allowed=false`; `apply` bloqueado com exit code `3`, sem criar
   `.ralph/install-manifest.json`.

3. **Ciclo complete de evolução** em projeto Git isolado:
   - `evolve --apply` → `EVL-20260812-0001`, `status=awaiting_acceptance`,
     manifesto novo presente, backup com árvore completa;
   - `--accept --apply` → `status=accepted` (schema `1.1.0`, backup com
     `8` arquivos registrados + árvore, journal with `before`/`after`);
   - drift em membro gerenciado → `rollback` bloqueado (exit `3`,
     `rollback_allowed=false`);
   - rollback limpo (sem drift) → `rollback --apply` exit `0`, árvore
     `harness/ralph` restaurada com `install.sh`, manifesto novo removido.

A suíte `test-installation.sh` cobre ainda os cenários de evolucão com
interrupção durante staging, restauração de estado interrompido, drift por
entrada extra, `already_pending` na repetição e remoção da instalação nova.

## Checks da CI portátil

`bash scripts/ci-portable.sh` executou na ordem e terminou verde:

`check-doc-sync`, `check-shell`, `test-installation`, `test-reproducibility`,
`test-feedback`, `test-provider-readiness`, `test-multiprovider`,
`test-ralph-method`, `test-ralph-reconciliation`, `test-ralph-noop-approval`,
`test-ralph-knowledge`, `test-ralph-metrics`, `test-ralph`, `test-opencode-policy`,
`test-opencode-adapter`.

## Documentação atualizada

- **ADR-0010** — estendido com a classificação `external_ralph_legacy` e o
  reconhecimento limitado da assinatura `bc-harness` na raiz aprovada
  `harness/ralph`;
- **`docs/STATUS.md`** — registra a regressão desta entrega e o relatório `0021`;
- **`docs/roadmap.md`** — fechamento da evolução do detector legado;
- **`CHANGELOG.md`** — entrada da validação de regressão de `0.8.0` → dígito de
  release do detector legado;
- **`docs/AGENT_GUIDE.md`** — registro da validação de regressão e desta release.

## Limitações registradas

- Não foi executado o **projeto-alvo original** (`teste-events-opencode` /
  `harness/ralph/` de campo): a validação usa a fixture versionada, evitando
  dependência de credencial, árvore externa ou estado de produto. Away da
  reprodução de campo fica documentada no relatório `0020`.
- Não foram executadas provas generativas de provider (campo real OpenCode).
  Os harnesses foram validados por suas suítes offline (`test-multiprovider`,
  `test-opencode-policy`, `test-opencode-adapter` e `ci-portable`); uma prova
  real de campo continua sendo o passo obrigatório para promoção desta release.
- O modo de migração permanece `quarantine_only`: não há adapter semântico por
  origem e nenhum ledger, workflow, prompt, credencial ou evento legado é
  importado.

## Decisão

A branch está verde para a revisão independente e a promoção. O commit da fase
e a promoção para `main` são realizados apenas pelo `scripts/ralph.sh` após a
revisão independente, conforme o fluxo do método.

## Origem

- detector: [`bin/ralph-init`](../../bin/ralph-init);
- contrato de detecção: [`schemas/ralph-installation-detection.schema.json`](../../schemas/ralph-installation-detection.schema.json);
- contrato de evolução: [`schemas/ralph-evolution.schema.json`](../../schemas/ralph-evolution.schema.json);
- fixture do padrão legado: [`tests/fixtures/bc-harness-legacy`](../../tests/fixtures/bc-harness-legacy);
- decisões: [`ADR-0010`](../adr/0010-deteccao-evolucao-de-ralph-externo.md), [`ADR-0011`](../adr/0011-evolucao-assistida-backup-rollback.md);
- handoff de campo: [`Relatório 0020`](0020-handoff-melhorias-detector-instalacao-2026-08-10.md).
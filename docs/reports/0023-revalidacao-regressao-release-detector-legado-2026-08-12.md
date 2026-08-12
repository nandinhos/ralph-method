# Relatório 0023 — Revalidação de regressão e release do detector legado (`bc-harness`)

## Estado

Revalidação da regressão `FEATURE-093-REGRESSION-RELEASE` (attempt-4) na branch
`feat/detector-bc-legacy`, após os fix de recuperação do supervisor (commit
`448a77f`, ADR-0013 / incidente 0013) e de prontidão de provider com SIGPIPE
(commit `596e2c1`). Todos os checks verdes. A promoção para `main` permanece
condicionada à revisão independente e ao commit único da fase, que são de
responsabilidade do `scripts/ralph.sh` e não desta sessão.

## Objetivo

Confirmar de forma determinística que a detecção e a evolução da instalação
Ralph legada `bc-harness` (features `091-DETECT-BC-LEGACY` e
`092-EVOLVE-BC-LEGACY`) continuam verdes após os dois fix incorporados desde o
relatório `0021`, incluindo a regressão completa da CI portátil, o bloqueio
fail-closed do `apply` comum e o ciclo evolve → aceite → drift → rollback em
fixture isolada — sem executar o projeto-alvo original.

## Ambiente

| Item | Valor |
|---|---|
| Branch | `feat/detector-bc-legacy` (HEAD `596e2c1`) |
| Ralph Method | `0.8.0` |
| PHP | `8.4.1` (cli) |
| Árvore de trabalho | limpa no início e ao final da fase |
| Projeto-alvo original | não executado; padrão reproduzido por fixture `tests/fixtures/bc-harness-legacy` |
| Fix revalidados | `448a77f` (supervisor com novo fencing), `596e2c1` (falso negativo de SIGPIPE) |

## Resultado por etapa da fase

| # | Item da fase | Comando/confirmação | Resultado | Status |
|---|---|---|---|---|
| 1 | lint dos componentes alterados | `php -l` em `bin/ralph-control`, `bin/ralph-init`, `bin/ralph-trace`, `bin/ralph-monitor`, `bin/ralph-metrics`, `bin/ralph-doctor`, `adapters/opencode/parser.php`, `adapters/opencode/policy.php` | `No syntax errors detected` em todos | verde |
| 2 | shell limpo | `bash scripts/check-shell.sh` | `OK: shell limpo.` (27 arquivos `bash -n` + shellcheck) | verde |
| 3 | doc sincronizada | `bash scripts/check-doc-sync.sh` | `OK: guia de agente sincronizado com Ralph Method 0.8.0.` | verde |
| 4 | instalação por projeto | `bash scripts/test-installation.sh` | `OK: instalação, idempotência, ownership, desinstalação e preservação passaram.` | verde |
| 5 | reprodutibilidade | `bash scripts/test-reproducibility.sh` | `OK: bundle Git reproduzido em projeto independente; ...` | verde |
| 6 | regressão multiprovider e OpenCode | `bash scripts/test-multiprovider.sh`, `bash scripts/test-opencode-policy.sh`, `bash scripts/test-opencode-adapter.sh` | verdes | verde |
| 7 | CI portátil | `bash scripts/ci-portable.sh` | 15 checks verdes (inclui `test-provider-readiness` e `test-ralph-method` com o fix de SIGPIPE e os 163 asserts) | verde |
| 8 | instalação neutra permitida | plano em projeto com `.ralph/` sem marcador | `status=not_found`, `apply_allowed=true`, `apply` exit `0` com manifesto publicado | verde |
| 9 | `harness/ralph/` bloqueia apply comum | plano em fixture `bc-harness-legacy` | `detected`, `external_ralph_legacy`, `family=bc-harness`, `legacy_type=legacy_directory`, `apply_allowed=false`, `apply` exit `3` sem manifesto | verde |
| 10 | evolve / aceite / drift / rollback em fixture | ciclo em fixture isolada | ver seção própria | verde |
| 11 | relatório numerado | este documento | `0023` | verde |
| 12 | docs de release atualizadas | ADR, STATUS, roadmap, changelog, guia | ver seção própria | verde |
| 13 | limitações registradas | sem executar o projeto-alvo original | ver seção própria | verde |
| 14 | commit e promoção | não criados nesta sessão | guardado para a revisão independente e o `ralph.sh` | condicionado |

## Confirmações diretas (fixture isolada)

Executadas fora da suíte, para evidência independente do reateste:

1. **Instalação neutra continua permitida**: projeto com `.ralph/project-notes.txt`
   (sem marcador conhecido) → `ralph_installation.external.status=not_found`,
   `apply_allowed=true`, `apply` com exit code `0` e manifesto publicado.

2. **`harness/ralph/` bloqueia o apply comum**: fixture
   `tests/fixtures/bc-harness-legacy/harness/ralph` → `status=detected`,
   `classification=external_ralph_legacy`, `family=bc-harness`,
   `legacy_type=legacy_directory`, `apply_allowed=false`; `apply` bloqueado com
   exit code `3`, sem criar `.ralph/install-manifest.json`.

3. **Ciclo completo de evolução** em projeto Git isolado:
   - `evolve --apply` → `EVL-20260812-0001`, `status=awaiting_acceptance`,
     manifesto novo presente, backup com árvore completa e membro aninhado;
   - `--accept --apply` → `status=accepted` (schema `1.1.0`, backup com
     `8` arquivos registrados + árvore);
   - drift em membro gerenciado → `rollback` bloqueado (exit `3`,
     `status=blocked`, `rollback_allowed=false`);
   - rollback limpo (sem drift) → `rollback --apply` exit `0`, árvore
     `harness/ralph` restaurada com modo `0750`, symlink interno preservado e
     manifesto novo removido.

## Checks da CI portátil

`bash scripts/ci-portable.sh` executou 15 checks na ordem e terminou verde com
`OK: CI portátil concluída sem credenciais ou geração real.`:

`check-doc-sync`, `check-shell`, `test-installation`, `test-reproducibility`,
`test-feedback`, `test-provider-readiness` (com o fix de SIGPIPE),
`test-multiprovider`, `test-ralph-method`, `test-ralph-reconciliation`,
`test-ralph-noop-approval`, `test-ralph-knowledge`, `test-ralph-metrics`,
`test-ralph` (163 asserts verdes), `test-opencode-policy`, `test-opencode-adapter`.

## Documentação atualizada

- **ADR-0010** — nota de revalidação após o hardening do supervisor;
- **`docs/STATUS.md`** — registra o reateste desta entrega e o relatório `0023`;
- **`docs/roadmap.md`** — registro do reateste da regressão do detector legado;
- **`CHANGELOG.md`** — entrada da revalidação na preparação `0.8.1`;
- **`docs/AGENT_GUIDE.md`** — evidência atualizada para o relatório `0023`.

## Limitações registradas

- Não foi executado o **projeto-alvo original** (`teste-events-opencode` /
  `harness/ralph/` de campo): a validação usa a fixture versionada, evitando
  dependência de credencial, árvore externa ou estado de produto. A via da
  reprodução de campo fica documentada no relatório `0020`.
- Não foram executadas provas generativas de provider (campo real OpenCode).
  Os harnesses foram validados por suas suítes offline (`test-multiprovider`,
  `test-opencode-policy`, `test-opencode-adapter` e `ci-portable`); uma prova
  real de campo continua sendo o passo obrigatório para promoção desta release.
- O modo de migração permanece `quarantine_only`: não há adapter semântico por
  origem e nenhum ledger, workflow, prompt, credencial ou evento legado é
  importado.
- O reateste cobre o comportamento supervisionado via `test-ralph-method.sh` e
  `test-ralph-reconciliation.sh`; a evidência de retry com novo fencing está no
  relatório `0022`.

## Decisão

A branch está verde para a revisão independente e a promoção. O commit da fase
e a promoção para `main` são realizados apenas pelo `scripts/ralph.sh` após a
revisão independente, conforme o fluxo do método.

## Origem

- detector: [`bin/ralph-init`](../../bin/ralph-init);
- contrato de detecção: [`schemas/ralph-installation-detection.schema.json`](../../schemas/ralph-installation-detection.schema.json);
- contrato de evolução: [`schemas/ralph-evolution.schema.json`](../../schemas/ralph-evolution.schema.json);
- fixture do padrão legado: [`tests/fixtures/bc-harness-legacy`](../../tests/fixtures/bc-harness-legacy);
- decisões: [`ADR-0010`](../adr/0010-deteccao-evolucao-de-ralph-externo.md), [`ADR-0011`](../adr/0011-evolucao-assistida-backup-rollback.md), [`ADR-0013`](../adr/0013-retry-do-supervisor-com-novo-fencing.md);
- handoff de campo: [`Relatório 0020`](0020-handoff-melhorias-detector-instalacao-2026-08-10.md);
- revalidação anterior: [`Relatório 0021`](0021-regressao-release-detector-legado-2026-08-12.md).

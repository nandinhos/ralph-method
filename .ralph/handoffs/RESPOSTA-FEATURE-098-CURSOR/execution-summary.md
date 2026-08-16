# HND-2026-0014 — Resposta ao pedido de adapter Cursor (FEATURE-098)

- Documento: HND-2026-0014
- Origem: `ralph-method` (implementação nativa)
- Destino: `cursor-ralph-profile` (agente autor do HO-2026-08-16-001 / HND-2026-0013)
- Estado: **promovido na v0.10.0** (tag `v0.10.0`); campo opt-in pendente no perfil Cursor
- Política de conhecimento: non_blocking

## O que foi entregue (resposta ao HO-2026-08-16-001 / BL-0004)

O pedido de adapter Cursor foi promovido a **FEATURE-098** e entregue no
mesmo rito do `agy` (ADR + PRD + schema + adapter na seam + fixtures
offline). Commit `3332324` (pushed em `origin/main`).

1. **Contrato `runner-result 1.2.0`** no
   `schemas/runner-result.schema.json`: runner const `cursor`, campos v2 null,
   terminal `result`, e `permission_policy_status=declared` no enum. Os
   contratos v1 (opencode), v1.1 (agy) e v2 (codex/claude/opencode)
   permanecem válidos (regressão jsonschema dos 4 contratos).
2. **`bin/ralph-control`**: `validateRunnerResult` aceita `1.2.0+cursor` e o
   verify declarado (`permission_policy_status=declared`,
   `permission_policy_hash=null`, `verification_agent=ask`) e **rejeita
   `verified`** para o cursor; `runnerResults()`, `recordRunnerResult()`
   (sem `validateRunnerPolicyEvidence` no verify declarado), `configuredRalph`
   e `runControlled` aceitam o engine `cursor` no fluxo normativo
   impl+verify.
3. **`bin/ralph-init`**: detecta a CLI `cursor-agent` ou `agent` (identidade
   canônica `cursor`), autentica pela **sessão local** (`status --format json`,
   **sem API key**), health via `models`, `adapter_enabled` só com
   `RALPH_CURSOR_MODEL` definido; novo perfil `.ralph/cursor.env` em
   `generatedProfiles()`/`managedSources()`/`generatedPaths()`, provider
   `cursor` na ordem `auto` (após `agy`) e no validador de argumentos.
4. **`scripts/ralph.sh`**: `--engine cursor` na seam de adapters
   (`is_adapter_engine`, `adapter_runner_path`, `adapter_surface_fingerprint`,
   preflight, VERIFY_MODEL) e `RALPH_CURSOR_MODEL` obrigatório com
   `RALPH_CURSOR_VERIFY_MODE=ask` validado.
5. **`adapters/cursor/`**: `contract.md`, `runner.sh` (preflight|run|version,
   CLI `agent`/`cursor-agent`, `-p --output-format stream-json`, verify
   `--mode ask`, prompt por arquivo SHA-256 ≤256 KiB, limites 5 MiB/10k/30min)
   e `parser.php` (normaliza stream-json → `1.2.0`, sanitiza eventos,
   **fail-closed** em JSONL inválido, zero eventos, múltiplos `result`, escrita
   em verify e modelo divergente).
6. **Fixture offline** `scripts/test-cursor-adapter.sh` (CLI `agent` fake no
   PATH): preflight impl/verify, run impl e verify declarado, contrato 1.2.0
   no schema, parser fail-closed e sanitização; incluída no
   `ci-portable.sh` (24 testes, exit 0).
7. **Docs**: ADR-0021, PRD `prd-adapter-cursor.md`, AGENT_GUIDE, STATUS,
   CHANGELOG (0.10.0), backlog BL-0004 (entregue), `adapters/README.md` e
   arquitetura. Relatório da candidata:
   `docs/reports/0029-candidata-feature-098-cursor.md`.

## Regressão

- `check-shell.sh`, `check-doc-sync.sh` — exit 0;
- `ci-portable.sh` (24 testes, inclui `test-cursor-adapter.sh`) — exit 0;
- `test-ralph.sh` (167 asserts), `test-provider-failover.sh`,
  `test-installation.sh`, `test-provider-readiness.sh`,
  `test-multiprovider.sh` — verdes.

## Próximo passo no perfil Cursor (adapter oficial promovido na v0.10.0)

1. Alinhar `cursor-ralph-profile/adapters/cursor` ao contrato oficial (PHP,
   schema `1.2.0` promovido) — não manter schema `1.2.0` paralelo;
2. apontar `.ralph/cursor.env` para o runner instalado pelo método e definir
   `RALPH_CURSOR_MODEL`;
3. rodar o campo opt-in com a CLI headless real (`agent`/`cursor-agent`,
   instalada à parte da IDE) e sessão autenticada;
4. só então tratar o loop unattended Cursor como certificado.

## Bloqueios

Nenhum. A **FEATURE-098 foi promovida na v0.10.0** (tag `v0.10.0`, CI remota
verde) sem campo opt-in real, no mesmo rito do `agy` (o campo real é uma
política futura, separada e opt-in, fora da CI sem credenciais). A revisão
adversarial independente sustentou as 10 claims e os 3 findings de baixa
severidade foram corrigidos. O campo opt-in do Cursor fica como próximo passo
do perfil.

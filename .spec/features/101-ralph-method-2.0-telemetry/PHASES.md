# FEATURE-101 — Ralph Method 2.0: telemetria contínua em tempo real (Onda 1)

Referências:

- [`PROJECT-DESCRIPTION.md`](PROJECT-DESCRIPTION.md)
- [`USER-STORIES.md`](USER-STORIES.md)
- [`docs/incidents/0013-retry-stale-reutilizava-lease.md`](../../../docs/incidents/0013-retry-stale-reutilizava-lease.md)
- [`docs/incidents/0018-bloco-deixa-arvore-suja-e-retry-trava.md`](../../../docs/incidents/0018-bloco-deixa-arvore-suja-e-retry-trava.md)

Invariantes em todas as fases:

- `bin/ralph-control` permanece a única autoridade de transição;
- o stream de telemetria é **sanitizado** (nunca prompts, respostas completas,
  segredos, caminhos absolutos ou conteúdo bruto de candidatos);
- o ledger continua íntegro: eventos novos validados pela hash chain e pelos
  enums de `$eventTypes`; leitor compatível `1.0.0`–`1.3.0`, rejeita `1.4.0`
  (fail-closed);
- `knowledge_policy.mode: non_blocking` preservado: liberar a feature e
  decidir a lição continuam decisões separadas;
- `test_command`: `bash scripts/ci-portable.sh`;
- cada feature altera código ou scripts versionados; commits somente após os
  cinco gates verdes;
- o `ralph-watch` não tem dependências novas (PHP/bash puro) e a CI portátil
  permanece sem Laravel/Postgres.

## Phase 1: Contrato de telemetria (schema + eventos)

**Goal:** emitir o stream sanitizado de progresso no ledger sem quebrar o
contrato existente. · **Covers:** US-1.1

- [ ] **Task:** promover `RALPH_SCHEMA_VERSION` para `1.3.0` em
  `bin/ralph-control` e adicionar `telemetry.activity`,
  `telemetry.heartbeat_rich`, `gate.started`, `gate.stalled`,
  `debug.progress`, `knowledge.telemetry` ao `$eventTypes`, com
  `RALPH_COMPATIBLE_SCHEMA_VERSIONS` aceitando `1.0.0`–`1.3.0` e rejeitando
  `1.4.0` (fail-closed).
  - **Acceptance criteria:** `bin/ralph-control verify` aceita ledger com
    eventos novos; tipo desconhecido → `event.rejected`; regressão v1.x
    preservada em fixture.
- [ ] **Task:** emitir `telemetry.activity` sanitizado durante o bloco
  controlado (`runControlled`), com `activity_preview`, `elapsed`,
  `idle_seconds`, `phase` — reutilizando `sanitize()`/`feedback_redact` para
  redigir em vez de rejeitar.
  - **Acceptance criteria:** fixture com canário de segredo e UTF-8 inválido
    comprova sanitização; evento não rejeita o bloco (redação, não rejeição).
- [ ] **Task:** enriquecer `command.heartbeat` com `position`, `eta_seconds`
  (derivado do histórico da feature) e `gate_age` quando em `awaiting_gates`,
  mantendo campos antigos para retrocompat.
  - **Acceptance criteria:** monitor e status continuam lendo os campos
    antigos; campos novos opcionais não quebram consumidores.

## Phase 2: Watchdog de gates

**Goal:** alertar `gate_stalled` antes de travar e nunca esperar em vão.
**Depends on:** Phase 1 · **Covers:** US-1.2

- [ ] **Task:** registrar `gate.started` (gate, attempt, started_at) ao entrar
  em `awaiting_gates` no pipeline do supervisor, idempotente por retry.
  - **Acceptance criteria:** replay de `awaiting_gates` não duplica
    `gate.started`; relógio injetável (`RALPH_TEST_CLOCK_EPOCH`) determinístico.
- [ ] **Task:** no ciclo do supervisor, derivar idade de cada gate do ledger e
  emitir `gate.stalled` acima de `RALPH_GATE_STALL_AFTER` (default 600s) com
  `gate`, `age_seconds`, `threshold`; acima de `RALPH_GATE_MAX_AGE` (default
  3600s) → `recovery_required` explícito.
  - **Acceptance criteria:** fixture com gate travado gera `gate.stalled` no
    limiar e `recovery_required` no horizonte sem espera real; feedback do
    supervisor exibe o alerta.
- [ ] **Task:** expor `gate_ages` no `ralph-monitor --once --json` (read-only).
  - **Acceptance criteria:** snapshot inclui idade por gate sem mutar ledger.

## Phase 3: Terminal dashboard (ralph-watch)

**Goal:** TUI em tempo real sem dependências novas. · **Depends on:** Phase 1
**Covers:** US-1.3

- [ ] **Task:** criar `bin/ralph-watch` (PHP puro) com leitura delta por mtime
  de `events.jsonl` + feedback, renderização ANSI (health, feature/attempt,
  gates com idade, fila, última atividade sanitizada), refresh default 1s.
  - **Acceptance criteria:** `php bin/ralph-watch --workflow <id>` roda sem
    deps externas; `--once --json` imprime snapshot válido; ledger ausente
    mostra estado explícito sem travar.
- [ ] **Task:** modo não-TTY (`--once`/pipe) e restauração de terminal no
  SIGINT; `php -l` limpo.
  - **Acceptance criteria:** `ralph-watch --once --json | jq .` exit 0;
    fixture comprova delta por mtime.
- [ ] **Task:** documentar `ralph-watch` no AGENT_GUIDE e no README.
  - **Acceptance criteria:** `check-doc-sync.sh` verde; guia descreve uso.

## Phase 4: Systematic debugging ao vivo

**Goal:** debug visível no stream com causa, hipóteses e validação oficial.
**Depends on:** Phase 1 · **Covers:** US-2.1

- [ ] **Task:** emitir `debug.progress` durante `runSystematicDebug` (início,
  hipóteses confirmadas/rejeitadas, referências Context7/official) com
  conteúdo sanitizado e `cause_kind` do contrato atual.
  - **Acceptance criteria:** fixture com comando de debug fake publica
    progresso; nenhum prompt/trecho sensível; relatório final `DBG-*` segue
    o contrato oficial.
- [ ] **Task:** exibir o debug ao vivo no `ralph-watch` e incluir `debug` no
  snapshot do monitor (read-only).
  - **Acceptance criteria:** TUI mostra debugging em andamento com status;
    monitor expõe `debug.progress` mais recente.

## Phase 5: Conhecimento em tempo real

**Goal:** candidatos LES e decisões visíveis no stream. · **Depends on:**
Phase 1 · **Covers:** US-2.2

- [ ] **Task:** emitir `knowledge.telemetry` ao criar candidato (após
  `feature.released`) e ao curar/rejeitar/skipped/review_required, com apenas
  título/categoria/tópicos sanitizados.
  - **Acceptance criteria:** fixture de curadoria gera telemetria por decisão;
    `knowledge_policy.mode: non_blocking` preservado; sem conteúdo bruto.
- [ ] **Task:** exibir fila de conhecimento no `ralph-watch` e no monitor
  (read-only), com contagem por status.
  - **Acceptance criteria:** TUI lista candidatos pendentes/curados; monitor
    JSON inclui `knowledge_summary` sem mutar ledger.

## Phase 6: Cockpit consumindo o stream

**Goal:** cockpit lê a mesma fonte do terminal, sem regex em stderr.
**Depends on:** Phases 1–5 · **Covers:** US-3.1

- [ ] **Task:** `RalphIngestor` ingere `telemetry.*`, `gate.started`,
  `gate.stalled`, `debug.progress`, `knowledge.telemetry` no read-model.
  - **Acceptance criteria:** `ralph:ingest --rebuild` reproduz projeção;
    eventos novos aparecem nas visões Eventos/Gates; Pest cobre ingest.
- [ ] **Task:** remover decisão por `preg_match` em stderr do supervise
  (`RalphLauncher::exitReasonFromLog`) e usar estado do controlador + stream.
  - **Acceptance criteria:** `test-cockpit-diagnose.sh` verde sem parsing de
    log; ADR-0022 emendado (fonte única: stream + controlador).
- [ ] **Task:** regressão completa: `ci-portable.sh` verde (sem Laravel),
  `test-ralph-method.sh` com eventos novos, docs/STATUS atualizado.
  - **Acceptance criteria:** suíte portátil 100% verde; STATUS documenta a
    Onda 1; handoff com evidência dos 5 gates por feature.

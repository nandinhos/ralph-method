# FEATURE-102 — Ralph Method 2.0: hardening de segurança (Onda 2)

Referências:

- [`PROJECT-DESCRIPTION.md`](PROJECT-DESCRIPTION.md)
- [`USER-STORIES.md`](USER-STORIES.md)
- [`DATABASE-SCHEMA.md`](DATABASE-SCHEMA.md)
- `.spec/features/101-ralph-method-2.0-telemetry/PHASES.md` (ritual das
  fases que esta onda herda)
- `docs/reports/relatorio-tempo-onda1.md` (métricas herdadas)
- `docs/handoffs/HO-2026-08-21-onde2-planejamento.md` (handoff da onda)

Invariantes em todas as fases:

- `bin/ralph-control` permanece a única autoridade de transição;
- nenhuma feature introduz dependência nova (PHP/bash puro); o `ralph-watch`
  da Onda 1 e o `ralph-time-report` continuam sendo os instrumentos de
  observabilidade e métrica;
- o ledger continua íntegro: cada evento novo é validado pela hash chain
  e pela nova `RALPH_KNOWN_EVENT_TYPES` (Feature 102D);
- `knowledge_policy.mode: non_blocking` preservado;
- `test_command`: `bash scripts/check-shell.sh && bash scripts/test-ralph-method.sh`
  (gate leve durante self-host; suite `ci-portable.sh` apenas no release);
- cada feature altera código ou scripts versionados; commits somente após
  os **cinco** gates verdes;
- O ciclo de recovery permanece alinhado (commit `e993c6d`): `recovery_required`
  → systematic debugging → `beginFailedRetry preserve-tree` →
  `RALPH_RECONCILE_DIRTY=1` → ralph.sh continua sobre a árvore parcial.

## Phase 1: sanitize() redige em vez de rejeitar (Feature 102A)

**Goal:** `sanitize()` nunca aborta o bloco; ele redacta o trecho sensível e
prossegue. **Covers:** US-2.1, US-2.2

- [ ] **Task:** em `bin/ralph-control`, alterar `sanitize()` para retornar
  string redigida (`[REDACTED:tipo]` por padrão detectado) e **não** chamar
  `fail()` por padrão de segredo. Tipos reconhecidos na v1: `token`,
  `aws_secret`, `private_key`, `db_url`, `bearer`, `cookie`.
  - **Acceptance criteria:** fixture canário `tests/fixtures/redaction/canary-text.txt`
    com `github_token=...` produz saída com `[REDACTED:token]` e nenhum
    `fail()`. Suite `scripts/test-sanitize-redact.sh` verde.
- [ ] **Task:** em `appendEventUnlocked`, quando o conteúdo sanitizado contém
  `[REDACTED:*]`, registrar `facts.redacted_count` e `facts.redacted_kinds` no
  evento gerado e `facts.path` (sem o trecho original).
  - **Acceptance criteria:** `event.redacted` no ledger após redação contém
    apenas kinds + path + feature_key; nenhum valor redigido vaza. Teste
    confirma hash chain íntegra após 100 redações.
- [ ] **Task:** `bin/ralph-diagnose.php` (diagnóstico read-only do
  systematic debugging) detecta `redacted_count > N` no ledger e emite
  alerta no relatório de debugging sem mostrar o trecho.
  - **Acceptance criteria:** relatório `DBG-*.md` com redacted não contém
    o valor; apenas o marker. `bash scripts/check-shell.sh` verde.

## Phase 2: Cursor rebaixado até prova completa (Feature 102B)

**Goal:** Cursor só roda em produção com `promoted=true` — opt-in declarado
não basta. **Depends on:** Phase 1 (sanitize preservado) · **Covers:** US-2.3

- [ ] **Task:** estender `bin/ralph-control provider-status` (e saída do
  `--json`) com o caminho de promoção por adapter: `optin`, `adversarial`,
  `hero`, `promoted`. Persistir o estado por adapter em
  `.ralph/adapter-promotion/<engine>.json`.
  - **Acceptance criteria:** `provider-status --format json` retorna os 4
    campos para cada adapter; campo `promotion_blockers` lista o que falta
    (`["adversarial"]`, `["hero"]`, etc.). Teste confirma retrocompat da
    saída v1 para adapters já promovidos.
- [ ] **Task:** criar `tests/test-cursor-adversarial.sh` com pelo menos 3
  cenários hostis (input malicioso, comando fora de allowlist, claim divergente)
  que **devem falhar** quando o Cursor está rebaixado e devem passar quando
  reativado com prova.
  - **Acceptance criteria:** exit code não-zero com `promoted=false` e
    `fail('cursor rebaixado; rode tests/test-cursor-adversarial.sh e test-cursor-hero.sh')`.
- [ ] **Task:** criar `tests/test-cursor-hero.sh` que executa um cenário
  end-to-end em checkout de campo (init + claim + run + 5 gates com
  Cursor como engine primário) e exige exit 0.
  - **Acceptance criteria:** exit 0 em hero flow. Sem isso, `promoted.hero=false`.
- [ ] **Task:** escrever `docs/adr/ADR-0033-cursor-promotion.md` (decisão +
  consequências). Registrar a métrica `promotion_blockers` na
  document-id registry do método.
  - **Acceptance criteria:** ADR cita opt-in da FEATURE-100A (relatório `0031`)
    e justifica o bloqueio até prova completa.

## Phase 3: policy_violation → `status: failed` (Feature 102C)

**Goal:** políticas violadas viram `status: failed` + `cause_kind:
harness_defect`, **não** `feature_bug`. Recovery não reinicia enquanto a
policy não for reconciliada. **Depends on:** Phase 1 · **Covers:** US-2.4, US-2.5

- [ ] **Task:** em `bin/ralph-control`, no caminho que chama `debug.rejected`
  (e `feature_bug_committed`), separar a classificação de causa: `debug`
  só classifica `feature_bug` quando houver `evidence_refs` em código;
  sem `evidence_refs`, classifica `harness_defect` e `reason: policy_violation`.
  - **Acceptance criteria:** fixture `tests/fixtures/policy/divergence.json`
    em `policy_violation` registra `recovery.required` com `cause_kind:
    harness_defect`; nunca `feature_bug`. Métrica da onda
    (`grep '"cause_kind": *"feature_bug".*policy_violation' events.jsonl`) retorna `0`.
- [ ] **Task:** `supervise` chama `supervisorRecordRequiredRecovery` (e não
  `beginFailedRetry`) quando `cause_kind=harness_defect` e `execution_policy_hash`
  diverge do congelado.
  - **Acceptance criteria:** supervisor NÃO inicia nova tentativa após
    `recovery.required/policy_violation`; lock `policy.lock` impede nova
    claim até `reconcile` ou re-init.
- [ ] **Task:** `approveFeature` rejeita resultado com
  `status: failed` e `reason: policy_violation` e exige recovery explícito.
  - **Acceptance criteria:** tentativa de approve de resultado `failed` por
    policy devolve mensagem clara e não altera estado.

## Phase 4: Validação centralizada de tipo de evento (Feature 102D)

**Goal:** `appendEvent` rejeita `type` desconhecido via enum canônica,
sem abrir o hash chain — `event.rejected` no lugar de pane ad-hoc.
**Depends on:** Phase 1 · **Covers:** US-2.6

- [ ] **Task:** introduzir enum canônica `RALPH_KNOWN_EVENT_TYPES` em
  `bin/ralph-control` cobrindo todos os tipos da Onda 1 + novos
  (`event.rejected`, `policy.failed`, `telemetry.redacted`,
  `knowledge.curated`). Carregar via `loadKnownEventTypes()` e validar em
  `appendEventUnlocked`.
  - **Acceptance criteria:** enum completa em `tests/fixtures/events/known-types.json`;
    suite `scripts/test-ralph-method.sh` continua verde; tipo em `enum`
    prossegue; tipo fora da enum registra `event.rejected` com
    `idempotency_key` único.
- [ ] **Task:** teste de fuzz de `appendEvent` (100 tipos aleatórios
  inválidos) registra 100 `event.rejected` e nenhum evento com tipo fora da
  enum canônica.
  - **Acceptance criteria:** ledger após fuzz: 100 entradas `event.rejected`,
    0 entradas com tipo inválido, hash chain íntegra. Teste determinístico
    com `RALPH_TEST_CLOCK_EPOCH`.

# FEATURE-100 — Trace Cockpit hero flow e campo Cursor

Referências:

- [`docs/prd/prd-trace-cockpit.md`](../../../docs/prd/prd-trace-cockpit.md)
- [`docs/adr/0022-cockpit-somente-leitura.md`](../../../docs/adr/0022-cockpit-somente-leitura.md)
- [`docs/backlog.md`](../../../docs/backlog.md) (`BL-0004` campo opt-in)
- [`docs/reports/0029-candidata-feature-098-cursor.md`](../../../docs/reports/0029-candidata-feature-098-cursor.md)

Invariantes em todas as fases:

- `bin/ralph-control` permanece a única autoridade de transição;
- o cockpit não aprova gate, não escolhe feature e não inventa plano ausente;
- `test_command`: `cd apps/cockpit && php artisan test`;
- cada feature altera código ou scripts versionados — nada de “validar que o
  manifesto existe” como entrega principal;
- commits somente após gates verdes quando houver código.

## Phase 1: Campo opt-in Cursor (`BL-0004`)

- [x] **Task:** criar `scripts/test-cursor-field.sh` espelhando o rito do
  `test-agy-field.sh` (repo descartável, prompts sanitizados, impl + verify
  declarado, terminal `result`).
  - **Acceptance criteria:** o script falha sem CLI/sessão; com
    `agent status --format json` autenticado termina exit 0; artefatos em
    `$TMP` não vazam prompt/resposta bruta; modelo observado no resultado.
- [x] **Task:** documentar variáveis de campo (`RALPH_CURSOR_CLI`,
  `RALPH_CURSOR_MODEL`, opt-in explícito) no `AGENT_GUIDE`.
  - **Acceptance criteria:** seção distingue CI offline (`test-cursor-adapter.sh`)
    de campo opt-in; nenhuma `CURSOR_API_KEY` versionada.
- [x] **Task:** registrar evidência sanitizada no relatório candidato.
  - **Acceptance criteria:** `docs/reports/0031-cursor-field-20260817.md` com versão
    CLI, hashes de prompt, exit codes e limitações do verify declarado.

## Phase 2: Superfícies v1 com dados reais

- [x] **Task:** projetar candidatos de conhecimento no painel Memória durante
  ingest follow/rebuild.
  - **Acceptance criteria:** com `.ralph/knowledge-candidates/` populado no
    checkout observado, a UI lista itens sanitizados; vazio mostra estado
    `cockpit.memory.empty`; Pest cobre ingest → projeção.
- [x] **Task:** montar árvore de delegação a partir de eventos
  `attempt.started` / delegação no ledger e feedback.
  - **Acceptance criteria:** durante bloco Cursor, root `ralph-control` e filho
    `cursor` aparecem ordenados; reload mantém a árvore.
- [x] **Task:** fechar lacunas visuais do mockup nas visões Eventos e Gates
  (filtros, colunas, tokens do `.dc.html`).
  - **Acceptance criteria:** três visões navegáveis; gates board reflete
    `passed`/`pending`/`failed` do ledger; sem botão de aprovação.

## Phase 3: Hero flow browser

- [ ] **Task:** automatizar o fluxo Rodar Ralph → eventos ao vivo → pausa.
  - **Acceptance criteria:** com preflight verde e fila pendente, novo evento
    aparece na UI em menos de 3 s após gravar JSONL; SIGTERM no supervise
    iniciado pelo cockpit encerra o bloco sem mutar gate.
- [ ] **Task:** provar reload idempotente e rebuild do read-model.
  - **Acceptance criteria:** após `ralph:ingest --rebuild`, reload do browser
    reproduz o mesmo estado; apagar Postgres e reingestar restaura projeção.
- [ ] **Task:** exercitar Diagnosticar e Retomar quando fila em
  `recovery_required`/`debugging_required`.
  - **Acceptance criteria:** diagnóstico JSON 1.2.0 com `cause_kind` e
    evidência; recover só após causa corrigida no checkout; UI não expõe
    `approve`/`advance`/`release` em rota HTTP.

## Phase 4: Fechamento, adversarial e backlog

- [ ] **Task:** revisão adversarial independente do hero flow e do campo Cursor.
  - **Acceptance criteria:** finding crítico/alto bloqueia promoção; relatório
    anexado em `docs/reports/`.
- [ ] **Task:** sincronizar `STATUS`, `roadmap`, `backlog` (`BL-0004` campo),
  `apps/cockpit/README` e checklist da PRD §8.
  - **Acceptance criteria:** item aberto “prova de campo Cursor + browser”
    marcado concluído com link ao relatório; `ci-portable.sh` verde.

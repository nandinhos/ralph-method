# ADR-0023 — Snapshot 1.1.0: cobertura completa do mockup canônico

- **Status:** proposed
- **Date:** `2026-08-19`
- **Owner:** Equipe do Ralph Method

## Contexto

O branch `devin/1787100627-verificacao-ui-acompanhamento` entregou o snapshot `schemas/monitor-snapshot.schema.json` 1.0.0 com painel local em `bin/ralph-monitor serve --project <p>` (loopback 127.0.0.1:7777, somente leitura, 405/404 verificados). O relatório `docs/reports/0031-verificacao-ui-acompanhamento.md` lista **fora de escopo desta entrega** os itens B1, B2 e B3:

- **B1** — `started_at`/`elapsed_seconds` do workflow e por feature (mockup usa para "Tempo ativo")
- **B2** — Contadores `recovery` e `failover` no snapshot (mockup usa para card "Recovery")
- **B3** — Cores/severidade na timeline e nos eventos

Além desses três bloqueantes, o mockup `docs/design/ralph-method-trace-design/Ralph Trace Cockpit.dc.html` espera:

- Progresso por feature com `started_at`, `elapsed_seconds`, `runner_actual` (último provider que emitiu `delegation.completed`) e `progress_percent` (0..100 baseado em gates passados)
- Timeline com `severity` (`info|gate|recovery|warn`) + `tag` (`evento|gate|recovery`) por item
- Seção "Memória de engenharia" com até 5 lições/candidatos de `.ralph/knowledge-candidates/` (`id`, `title`, `kind`, `confidence`)
- Árvore de delegação rasa (até 3 nós): `root` (ralph-control) + último `delegation.completed` + último reviewer
- Gates com `elapsed_seconds` + `artifact_id` (do `facts.evidence.artifact_id` se presente)

O ADR-0022 estabelece que o cockpit é **consumidor externo** do canal JSONL e do `ralph-monitor --once --json`; não aprova gate, não escolhe feature, não troca provider. Toda derivação deve ser **função pura** sobre `workflow.json` (read-only) e `events.jsonl` (read-only), O(N) sobre eventos já lidos pelo monitor.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Estender 1.0.0 in-place** | Um único schema | Quebra consumidores que validam `schema_version`; migração forçada |
| **B — Congelar 1.0.0 e criar 1.1.0 aditivo** | Compatibilidade total; opt-in para UI nova; versionamento semântico claro | Dois schemas coexistentes por um ciclo |
| **C — Esperar a UI do `apps/cockpit/` em Laravel** | UI nativa resolve exibição | Atrasa feedback ao operador; mockup já define contrato |
| **D — Só melhorar UI client-side sem mudar contrato** | Zero mudança no núcleo | Impossível derivar `elapsed_seconds`, `runner_actual`, `severity`, `knowledge`, `delegation.tree` sem dados no snapshot |

**Recomendação: B.** Congelar 1.0.0 como `supported`, publicar 1.1.0 com campos **opcionais** (compatíveis com consumidores 1.0.0) e remover 1.0.0 no próximo ciclo maior.

## Decisão

Publicar `schemas/monitor-snapshot.schema.json` **1.1.0** com os acréscimos abaixo (todos opcionais). O `bin/ralph-monitor` passa a emitir `schema_version: "1.1.0"` quando houver pelo menos um campo novo preenchido; caso contrário, mantém 1.0.0 para não forçar migração.

### 1. Tempo do workflow (`snapshot.workflow`)

```json
"workflow": {
  "started_at": "2026-08-10T14:12:31Z",
  "elapsed_seconds": 6138
}
```

- `started_at`: derivado de `workflow.json#initialized_at` (se ausente, do primeiro `workflow.initialized` no `events.jsonl`)
- `elapsed_seconds`: `time() - started_at` no instante da coleta

### 2. Contadores operacionais (`snapshot.counters`)

```json
"counters": {
  "recovery_required": 2,
  "recovery_resolved": 1,
  "failover": 1,
  "released_features": 1
}
```

- `recovery_required`: contagem de eventos `recovery.required` no `events.jsonl` (mesma fonte que `ralph-metrics`)
- `recovery_resolved`: contagem de `recovery.resolved`
- `failover`: contagem de `provider.failover_started`
- `released_features`: contagem de `feature.released`

### 3. Por feature (`snapshot.features[].feature_meta`)

```json
"feature_meta": {
  "started_at": "2026-08-10T14:42:49Z",
  "elapsed_seconds": 3456,
  "runner_actual": "OpenCode",
  "progress_percent": 68
}
```

- `started_at`: primeiro `feature.claimed` ou `attempt.started` desta feature no `events.jsonl`
- `elapsed_seconds`: `time() - started_at` (se `started_at` ausente, `null`)
- `runner_actual`: `facts.runner` do último `delegation.completed` desta feature; se ausente, `facts.engine` do último `command.started`
- `progress_percent`: `(gates_passados / 5) * 100` arredondado; gates obrigatórios: `validation`, `quality`, `runtime_evidence`, `technical_review`, `curation`

### 4. Timeline severity (`snapshot.timeline[].severity`, `tag`)

```json
"timeline": [
  { "type": "gate.quality.passed", "severity": "gate", "tag": "gate", ... },
  { "type": "delegation.completed", "severity": "info", "tag": "evento", ... },
  { "type": "recovery.documented", "severity": "recovery", "tag": "recovery", ... },
  { "type": "command.failed", "severity": "warn", "tag": "evento", ... }
]
```

**Regras de derivação (função pura sobre `event.type`):**

| `event.type` prefix | `severity` | `tag` |
|---|---|---|
| `gate.*` | `gate` | `gate` |
| `recovery.*` | `recovery` | `recovery` |
| `command.failed`, `failure.detected`, `provider.capacity_limited` | `warn` | `evento` |
| demais (`feature.*`, `delegation.*`, `command.started|passed`, `knowledge.*`, `workflow.*`, `provider.failover_started`, etc.) | `info` | `evento` |

### 5. Knowledge resumido (`snapshot.knowledge.recent`)

```json
"knowledge": {
  "recent": [
    { "id": "LES-2026-004", "title": "Gate sem diagnóstico exige reprodução limpa", "kind": "lesson", "confidence": "high" },
    { "id": "CUR-2026-0003", "title": "Preview de captura deve tolerar UTF-8 incompleto", "kind": "candidate", "confidence": "medium" }
  ]
}
```

- Fonte: `.ralph/knowledge-candidates/` (candidatos `status: pending`) + `docs/engineering/lessons/*.yaml` (lições `status: validated`)
- Máximo 5 itens, ordenados por `created_at` decrescente
- **Nunca** inclui `prompt`, `response`, `token`, `handoff_path` ou `source`
- `kind`: `lesson` | `candidate` | `incident` | `pattern` | `anti-pattern`
- `confidence`: `high` | `medium` | `low` (do campo `confidence` da lição; candidatos usam `medium` por default)

### 6. Delegation tree rasa (`snapshot.delegation.tree`)

```json
"delegation": {
  "tree": [
    { "role": "root", "runner": "ralph-control", "status": "authority", "identity_status": "non_delegable" },
    { "role": "implementação", "runner": "OpenCode", "status": "completed", "identity_status": "verified" },
    { "role": "technical review", "runner": "ralph-review", "status": "completed", "identity_status": "read_only" }
  ]
}
```

- Fonte: `ralph-control trace-report --format json --workflow <id>` (já normalizado)
- Até 3 nós: (1) root `ralph-control`, (2) último `delegation.completed` (por timestamp) da feature atual, (3) último reviewer (`ralph-review` ou papel com `review` no nome) se houver
- Se feature sem delegação concluída, array contém só o root

### 7. Gates com elapsed (`snapshot.features[].gates[].elapsed_seconds`, `artifact_id`)

```json
"gates": {
  "quality": { "status": "passed", "elapsed_seconds": 134, "artifact_id": "EVD-2026-0046" }
}
```

- `elapsed_seconds`: diferença entre `gate.passed` (ou `gate.rejected`) e o `attempt.started` correspondente (mesmo `attempt` e `feature_key`)
- `artifact_id`: `facts.evidence.artifact_id` do evento `gate.passed` se presente; caso contrário `null`

## Consequências

### Positivas

- UI renderiza 100% do mockup canônico sem lógica client-side de derivação
- Contrato único e versionado; consumidores 1.0.0 continuam funcionando (campos opcionais)
- Toda derivação é O(N) sobre eventos já lidos pelo monitor (sem releitura de ledger)
- Nenhum segredo, prompt ou token no snapshot (knowledge carrega só metadados)
- Autoridade permanece no `ralph-control`; monitor continua observador passivo

### Negativas

- `bin/ralph-monitor` ganha ~150 linhas de derivação pura (ainda single-file PHP)
- Dois schemas coexistem até remoção do 1.0.0
- `knowledge.recent` exige leitura de diretório `.ralph/knowledge-candidates/` (já feito pelo `knowledge` command)

### Obrigações

- Todos os campos novos **devem ser opcionais** no JSON Schema (`required: []` mantido)
- `schema_version` emitido como `"1.1.0"` apenas quando houver dado novo; `"1.0.0"` caso contrário
- Nenhum campo pode aprovar gate, alterar lease, mudar provider ou iniciar feature
- Origem dos dados declarada no ADR: `workflow.json`, `events.jsonl`, `.ralph/knowledge-candidates/`, `ralph-control trace-report`
- Testes de regressão do monitor devem validar snapshot 1.1.0 contra mockup estático

## Gatilho para revisitar

Revisitar quando:

1. Um segundo checkout precisar ser observado simultaneamente (exige ingestor separado, não mudança de schema)
2. O `events.jsonl` de um bloco único passar de 50 MiB com hidratação lenta (exige streaming/incremental, não novo campo)
3. Houver requisito real de auth além de localhost (ADR-0022 já prevê)
4. O cockpit Laravel (`apps/cockpit/`) validar que todos os campos são consumidos sem processamento adicional

## Emenda — Backlog de polimentos P1/P2 (fora deste escopo)

| Item | Descrição | Prioridade |
|---|---|---|
| Sparkline de throughput | Mini-gráfico de eventos/hora nas últimas 2h no card "Tempo ativo" | P1 |
| Histórico de health | Array `health_history[]` com últimos 10 estados para trend | P1 |
| Filtro de timeline por severity | UI já tem botões; snapshot já entrega `severity`/`tag` | P1 (client-side) |
| Comparação de tentativas | `attempt_history[]` com `started_at`, `elapsed`, `gates`, `runner` por attempt | P2 |
| Knowledge graph links | `related_lessons[]` com `id` e `title` de lições com `topics` sobrepostos | P2 |
| Exportar snapshot assinado | `signature` (ed25519) do snapshot para auditoria externa | P2 |

Estes itens **não** alteram o contrato 1.1.0; são melhorias de UX ou observabilidade futura.
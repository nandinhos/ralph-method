# Ralph Method 2.0 — User Stories (Onda 1: telemetria contínua)

<!-- inputs: project-description.md@sha256:<gerado-no-ciclo> -->

## Overview

Operadores do Ralph Method precisam saber, em tempo real, o que o loop está
fazendo: qual feature, qual gate, quanto tempo em cada gate, o que o provider
está produzindo (sanitizado), o que o systematic debugging concluiu e o que a
camada de conhecimento decidiu. Hoje o sistema "parece travado" porque a
visibilidade é por polling e só muda em pontos de transição.

**User Types:**
- **Operador** — humano que roda `supervise` e acompanha o workflow.
- **Agente executor** — o próprio ralph-control/supervisor emitindo o stream.
- **Consumidor** — cockpit Laravel e scripts que leem o stream.

---

## 1. Telemetria contínua do ciclo

### US-1.1: Stream sanitizado de progresso
**As a** operador
**I want to** ver eventos de progresso contínuo (não só transições) no ledger
**So that** eu nunca precise perguntar "está travado?" sem um dado factual.

**Acceptance Criteria:**
- [ ] Novo tipo de evento `telemetry.*` emitido durante o bloco (heartbeat rico: atividade sanitizada do provider, posição, ETA)
- [ ] Eventos sanitizados: nenhum prompt/resposta/segredo/caminho absoluto no stream
- [ ] `ralph-control status` e monitor continuam funcionando (retrocompat)
- [ ] Ledger continua íntegro (hash chain valida os eventos novos)

**Expected Result:** o ledger mostra a atividade do ciclo em tempo real, sem
quebrar o contrato de eventos existente.

### US-1.2: Watchdog de gates com alerta
**As a** operador
**I want to** ser alertado quando um gate demora além do esperado
**So that** um gate preso não pareça um travamento silencioso.

**Acceptance Criteria:**
- [ ] Evento `gate.started` registra timestamp por gate ao entrar em `awaiting_gates`
- [ ] Idade do gate derivável do ledger (sem sidecar)
- [ ] Acima do limiar: evento `gate.stalled` + alerta no feedback; acima do horizonte: `recovery_required`
- [ ] Limiar/horizonte configuráveis por env (`RALPH_GATE_STALL_AFTER`, `RALPH_GATE_MAX_AGE`)
- [ ] Teste determinístico (relógio injetável)

**Expected Result:** um gate demorado gera alerta factual antes de travar.

### US-1.3: Terminal dashboard (ralph-watch)
**As a** operador
**I want to** acompanhar o workflow em tempo real no terminal
**So that** eu veja saúde, gates, fila e atividade sem abrir outra ferramenta.

**Acceptance Criteria:**
- [ ] `bin/ralph-watch --workflow <id>` renderiza TUI com refresh (default 1s)
- [ ] Mostra: saúde, feature/attempt, gates com idade, fila, última atividade sanitizada
- [ ] `--once --json` produz snapshot consumível (scripts/cockpit)
- [ ] Sem dependências novas (PHP/bash puro); leitura eficiente (delta por mtime)
- [ ] Falha de leitura (ledger ausente) mostra estado explícito, sem travar a TUI

**Expected Result:** o operador vê o sistema vivo a cada segundo.

## 2. Debugging e conhecimento visíveis

### US-2.1: Systematic debugging ao vivo
**As a** operador
**I want to** ver o debug sistemático em andamento (causa, hipóteses, validação)
**So that** um debugging longo não pareça travamento.

**Acceptance Criteria:**
- [ ] Eventos de progresso do debug (início, hipóteses confirmadas/rejeitadas, referências oficiais Context7/official) publicados no stream
- [ ] Conteúdo sanitizado (sem prompts, sem trechos de código sensível)
- [ ] Relatório final `DBG-*` continua o contrato oficial (retrocompat)
- [ ] O `ralph-watch` mostra o debug com status ao vivo

**Expected Result:** o operador vê o debugger trabalhando e sua validação com
documentação oficial em tempo real.

### US-2.2: Camada de conhecimento em tempo real
**As a** operador
**I want to** ver candidatos LES e decisões de curadoria no stream
**So that** eu saiba o que está virando memória sem abrir `.ralph/knowledge-candidates/`.

**Acceptance Criteria:**
- [ ] Candidato criado após `feature.released` emite evento de telemetria (não apenas `knowledge.candidate_created`)
- [ ] Decisões curadas/rejeitadas/skipped/review_required visíveis no stream
- [ ] `knowledge_policy.mode: non_blocking` preservado (liberar feature ≠ decidir lição)
- [ ] Nenhum conteúdo bruto de candidato no stream (só título/categoria/tópicos sanitizados)

**Expected Result:** a memória do método é visível e rastreável em tempo real.

## 3. Consumidores

### US-3.1: Cockpit consumindo o stream (sem parsing de stderr)
**As a** consumidor
**I want to** que o cockpit Laravel leia o stream de telemetria em vez de parsear stderr do supervisor
**So that** o diagnóstico exibido nunca "minta" por regex de log.

**Acceptance Criteria:**
- [ ] `apps/cockpit` ingesta os eventos `telemetry.*` e `gate.stalled`
- [ ] Removida a dependência de `preg_match` em stderr do supervise para decisão de causa
- [ ] Read-model continua reconstruível (`ralph:ingest --rebuild`)
- [ ] CI portátil permanece sem Laravel/Postgres

**Expected Result:** cockpit e terminal mostram o mesmo estado, da mesma fonte.

---

## Appendix: User Story Status

| ID | Story | Priority | Status |
|----|-------|----------|--------|
| US-1.1 | Stream sanitizado de progresso | High | Pending |
| US-1.2 | Watchdog de gates | High | Pending |
| US-1.3 | Terminal dashboard ralph-watch | High | Pending |
| US-2.1 | Systematic debugging ao vivo | Medium | Pending |
| US-2.2 | Conhecimento em tempo real | Medium | Pending |
| US-3.1 | Cockpit consumindo o stream | Medium | Pending |

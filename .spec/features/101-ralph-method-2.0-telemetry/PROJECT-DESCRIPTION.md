# Ralph Method 2.0 — Project Description

<!-- inputs: (cadeia de planejamento da Onda 1 — telemetria contínua) -->

## Overview

O **Ralph Method** é um control plane local e agnóstico de stack para execução
faseada de desenvolvimento com gates determinísticos, recuperação, handoff,
memória e trace de orquestração. A versão 1.x provou o modelo de autoridade
única (ledger hash-chain, lease/fencing, cinco gates) e a integração com
múltiplos harnesses (Codex, Claude CLI, OpenCode, agy, Cursor), mas sua
observabilidade é **por polling**: o supervisor decide saúde a cada
`--interval` (30s default), o que o provider está fazendo só aparece quando o
bloco termina, e um gate preso (ou um systematic debugging em execução) é
indistinguível de um sistema travado.

O **Ralph Method 2.0** ataca exatamente esse vazio com uma **camada de
telemetria contínua em tempo real**: um stream sanitizado de progresso no
ledger (bloco, gates, systematic debugging ao vivo com causa/hipóteses,
validação com documentação oficial Context7/official, candidatos de
conhecimento LES-YYYY-NNNN e curadoria), um **watchdog de gates** que alerta
`gate_stalled` antes de travar e um **terminal dashboard** (`ralph-watch`) que
mostra ao operador, a cada segundo, o que está acontecendo debaixo dos panos.
O cockpit Laravel existente passa a consumir o mesmo stream, em vez de
re-derivar estado por parsing de logs.

### Key Concepts

- **Autoridade única:** `bin/ralph-control` é a única autoridade de transição
  de estado, lease, fencing, locks, gates, recuperação e avanço da fila.
- **Ledger imutável:** `events.jsonl` com hash chain, idempotência e
  sanitização; nenhum outro componente grava estado global.
- **Cinco gates:** validation, quality, runtime_evidence, technical_review,
  curation — uma feature só avança com todos comprovados.
- **Telemetria contínua (novo):** eventos de progresso sanitizados emitidos
  pelo próprio controlador/supervisor/adapters durante o bloco — não apenas
  nos pontos de transição.
- **Watchdog de gates (novo):** deriva idade de cada gate no stream e alerta
  `gate_stalled` antes de travar; com horizonte máximo, nunca espera infinita.
- **Systematic debugging visível (novo):** o debug read-only publica causa,
  hipóteses e validação com documentação oficial (Context7/official) em tempo
  real, não só no relatório final.
- **Conhecimento visível (novo):** candidatos LES-YYYY-NNNN, curadoria,
  rejeição e skip aparecem no stream, separando "decidir lição" de "liberar
  feature" (knowledge_policy não bloqueante).
- **ralph-watch (novo):** TUI em PHP/bash puro, sem dependências novas, que
  lê o stream e renderiza saúde, feature atual, atividade do provider, idade
  dos gates e fila.

## Tech Stack

| Layer | Tecnologia |
|---|---|
| Control plane | PHP 8.2+ (binários em `bin/`) |
| Runner | bash (`scripts/ralph.sh`) |
| Adapters | PHP + bash por harness (`adapters/opencode|agy|cursor/`) |
| Persistência | arquivos JSONL no `.git/ralph-control/` (sem banco de produto) |
| UI consumidora | Laravel 13 + Livewire + Reverb em `apps/cockpit/` (opcional, fora da CI portátil) |
| Testes | bash scripts em `scripts/test-*.sh` + `ci-portable.sh` |

## Core Workflows

### 1. Execução supervisionada com telemetria

1. `ralph-control supervise --workflow <id>` inicia o ciclo;
2. o supervisor emite eventos de progresso contínuo (heartbeat rico com
   atividade do provider, posição na fila, ETA) no ledger;
3. o `ralph-watch` consome o stream e renderiza em tempo real;
4. cada gate em `awaiting_gates` tem idade monitorada; excedeu o limiar →
   `gate_stalled`; excedeu o horizonte → `recovery_required` explícito;
5. debugging/curadoria publicam causa, hipóteses, referências oficiais e
   decisões de conhecimento no stream;
6. o operador nunca fica com a impressão de travamento sem dado factual.

### 2. Watchdog de gates

1. feature entra em `awaiting_gates`;
2. o supervisor registra `gate.started` com timestamp por gate;
3. a cada ciclo, a idade do gate é comparada ao limiar (configurável por env);
4. acima do limiar: evento `gate.stalled` + linha de alerta no feedback;
5. acima do horizonte máximo: `recovery_required` (nunca espera infinita).

### 3. Terminal dashboard (ralph-watch)

1. `bin/ralph-watch --workflow <id> [--interval 1]` abre a TUI;
2. lê `events.jsonl` + feedback JSONL (tail eficiente, delta por mtime);
3. renderiza: saúde, feature/attempt, gates com idade, fila, última atividade
   sanitizada, candidatos de conhecimento;
4. `--once --json` para snapshot consumível por scripts e pelo cockpit.

## Open Questions

- Onde o stream sanitizado deve viver: eventos `1.3.0` novos no ledger vs.
  arquivo separado `telemetry.jsonl`? (ledger cresce; telemetria é volátil)
- O cockpit Laravel passa a ler o stream novo ou mantém o ingestor atual?

# Trace Cockpit — desenho da camada de visibilidade

Status: **scaffold nesta branch** (`feat/trace-cockpit`). O app vive em
`apps/cockpit/`. Traça a [PRD](../prd/prd-trace-cockpit.md) e o
[ADR-0022](../adr/0022-cockpit-somente-leitura.md). O mockup canônico é
[`Ralph Trace Cockpit.dc.html`](../design/ralph-method-trace-design/Ralph%20Trace%20Cockpit.dc.html).

## Contexto elicited

Um operador local, um checkout, um browser. Pico: dezenas de eventos por
minuto durante um bloco Cursor. Sem PII de produto, sem SLA, sem
multi-tenant. O pior bug possível é a UI *parecer* que aprovou um gate —
por isso não há ações de gate. O botão **Rodar Ralph** só dispara
`supervise` e permanece desabilitado fora do preflight. Com a fila
travada, **Diagnosticar** e **Retomar orquestrador** falam com o
controlador (debug read-only sobre manifesto/stderr/ledger, recover,
depois supervise com `--debug-command`) — ainda sem escolher feature
nem aprovar gate. Preflight recusa `supervise` se o `plan_file`
declarado não existir no checkout.

## Irreversíveis (decididos agora)

1. **Ownership:** o control plane continua dono do estado; o cockpit dono
   só da projeção e da apresentação.
2. **Contrato de entrada:** somente leitura de
   `.git/ralph-control/feedback/events.jsonl`,
   `.git/ralph-control/events.jsonl`,
   `bin/ralph-monitor --once --json` e candidatos de conhecimento.
3. **Contrato de saída:** Echo/Reverb com eventos de UI. Mutações
   permitidas: `supervise --workflow {id}` após preflight verde;
   `debug` com o comando read-only do cockpit; `recover` quando o cursor
   está em `recovery_required` ou `blocked`; SIGTERM no processo de
   supervise que o próprio cockpit disparou. Proibido em rota HTTP e
   como escolha de fila: approve, retry, advance, release, escolha de
   feature ou de provider.
4. **Isolamento:** árvore `apps/cockpit/` fora do `ci-portable.sh`.

## Reversíveis (deferidos)

Fila Redis vs `database`, Sail vs Compose artesanal, porta HTTP exata,
presença de Vite HMR. Decidir na implementação.

## Forma barata agora

```text
apps/cockpit/          Laravel 13 + Livewire 4 + Tailwind + Reverb
  docker-compose.yml   app, postgres, reverb (fila database)
  app/Ingest/          artisan ralph:ingest --follow
  app/Livewire/        TraceCockpit (três visões do design)
```

O ingestor faz *tail* incremental (offset em bytes + hash da última linha
válida). Cada fato novo: upsert da projeção + `broadcast()`. Livewire
escuta o canal `ralph.cockpit.{workflow_id}`. No reload, hidrata do
Postgres. `ralph:ingest --rebuild` apaga a projeção e relê os arquivos.

## Fontes × painéis

| Painel do design | Fonte | Campo típico |
|---|---|---|
| pulso “execução saudável” | monitor `health` | `ok` / `warning` / `error` / `complete` |
| anel de progresso | feedback `progress.percent` ∪ features do workflow | 0–100 |
| feature atual | workflow cursor + ledger | `feature_key`, `state`, `attempt`, `engine` |
| sequência autorizada | manifesto + ledger `feature.*` | released / running / pending |
| cinco gates | ledger `gate.*` | passed / pending / failed |
| timeline | ledger ∪ feedback | `type`/`event` + `detail` sanitizado |
| memória | knowledge candidates / lições | não bloqueante |
| delegação | ledger/trace | root `ralph-control`; filho = runner (ex.: `cursor`) |

O schema de feedback **não** será alargado para caber o mockup. Quem tem
título de feature e nome de gate é o ledger e o monitor.

## DNA visual (do `.dc.html`, não do HTML estático)

O upload `ralph-trace-web.html` usa Inter como fallback. O arquivo
`.dc.html` é a referência de produto:

| Token | Valor |
|---|---|
| Display | Space Grotesk 400–700, tracking negativo no H1 |
| Mono | JetBrains Mono 400–700 |
| Fundo | `#060e12` + radiais ciano/violeta + grid 44px |
| Texto | `#effaf7` · muted `#87a39f` |
| Lime | `#b9f55b` ( pulso, sucesso, HUD ok ) |
| Ciano | `#68e5db` ( acento, feature atual ) |
| Violeta | `#a98bff` ( autoridade / delegação ) |
| Amber | `#ffc76b` ( atenção: preflight sujo, health warning ) |
| Vermelho | `#ff7f91` ( trava: recovery/blocked/debugging, health error ) |
| Raio card | 18–22px · borda `rgba(173,219,213,.12)` |
| Motion | `rt-pulse`, `rt-sheen` na barra, tick 1s no tempo ativo |

O hero (`rt-hero-copy`) e o anel de porcentagem herdam o tom do
orquestrador: **ok** verde, **atenção** âmbar, **trava** vermelho
(`recovery_required` / `blocked` / `debugging_required` / health error).

Filament fica de fora: o mockup não é um resource admin.

## Seams e gatilhos de extração

| Seam | Forma barata agora | Gatilho |
|---|---|---|
| Ingestor | `artisan ralph:ingest` no mesmo container | JSONL > 50 MiB ou hidratação > 2 s |
| Checkout observado | `RALPH_PROJECT_ROOT` + mount RO | segundo checkout simultâneo |
| Auth | bind `127.0.0.1`, sem login | exposição além de localhost |
| Núcleo | PHP CLI existente, intocado | nunca: o cockpit não entra em `bin/` |

## O que o cockpit não lê

Credenciais, `.env` do projeto-alvo, prompts, stdout integral do provider,
leases em claro, proofs de política, `CURSOR_API_KEY`.

## Implementação (ordem)

1. Scaffold Laravel 13 em `apps/cockpit/` + Compose (Postgres, Reverb).
2. Models/migrations da projeção + comando `ralph:ingest` (rebuild + follow).
3. Livewire da visão **Tudo** fiel ao `.dc.html`.
4. Echo: deltas na timeline, pulso e percentual.
5. Visões **Eventos** e **Gates**.
6. Pest do cockpit (isolado) + prova de que `ci-portable.sh` ignora o app.
7. Prova de campo: bloco Cursor + browser no hero flow.

Cada passo prova o anterior. O núcleo (`bin/ralph-*`) não muda salvo se
faltar um campo já sanitizado no snapshot do monitor — e isso vira ADR
próprio, não atalho da UI.

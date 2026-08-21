# PLAN — Trace Cockpit hero flow e campo Cursor

## Objetivo

Fechar o que o backlog e o roadmap ainda deixam aberto após a FEATURE-098
(adapter Cursor offline) e a FEATURE-099 (smoke de manifesto/preflight): provar
**campo opt-in** com a CLI Cursor autenticada, completar superfícies v1 do
mockup que ainda não projetam dados reais e demonstrar o **hero flow** no browser
— pulso, feature, gates, timeline e ações permitidas (Rodar, Diagnosticar,
Retomar, Pausar) — com o Ralph executando trabalho **tangível** no checkout.

## Origem no backlog e no roadmap

| Fonte | Item | O que esta feature entrega |
|---|---|---|
| `BL-0004` | Adapter Cursor entregue offline; **campo opt-in pendente** | `scripts/test-cursor-field.sh` + smoke real sanitizado |
| `docs/roadmap.md` | Trace Cockpit: prova de campo com bloco Cursor e browser | Hero flow E2E com Reverb |
| `docs/prd/prd-trace-cockpit.md` | Aceite §8 (latência, reload, sem autoridade extra) | Checklist automatizado + relatório |
| `docs/reports/0029-candidata-feature-098-cursor.md` | Limitações: sessão real, adversarial | Evidência antes de fechar BL-0004 |

A FEATURE-099 permanece como fixture de **contrato** (manifesto, preflight,
ingest mínimo). Ela **não** substitui produto: tarefas como “versionar
manifesto” não movem código visível. Esta FEATURE-100 é o workflow executável
do checkout de campo observado pelo cockpit.

## Estratégia

1. campo Cursor no rito do `test-agy-field.sh` (impl + verify declarado, sem CI
   com credenciais);
2. ingestor e UI projetarem memória e delegação a partir de fatos reais do
   ledger/trace durante um bloco;
3. teste browser (Pest + Playwright ou equivalente já usado no repo) provando
   latência <3 s, reload idempotente e ausência de rotas proibidas;
4. relatório numerado + revisão adversarial antes de marcar campo no backlog.

## Decisões vinculantes

- workflow: `wf_trace_cockpit_hero`;
- runner primário: `cursor` (`primary_runner` / cadeia explícita);
- `test_command`: `cd apps/cockpit && php artisan test`;
- checkout de campo: `/tmp/ralph-cockpit-field` via
  `scripts/bootstrap-cockpit-field.sh` (manifesto 100 por default);
- o cockpit continua somente leitura para gates; mutações permitidas conforme
  ADR-0022;
- working tree limpa é pré-requisito de claim — o bootstrap deve excluir artefatos
  gerados localmente (`apps/` parcial, scripts de campo) do git status.

## Ordem e dependências

```text
Campo Cursor (100A)
  → Superfícies v1 com dados reais (100B)
  → Hero flow browser (100C)
  → Relatório, adversarial e docs (100D)
```

## Evidência mínima

- `scripts/test-cursor-field.sh` verde com sessão autenticada (opt-in local);
- `php artisan test` em `apps/cockpit/` verde;
- hero flow reproduzível: screenshot ou trace Playwright anexado ao relatório;
- `bash scripts/ci-portable.sh` continua verde (cockpit fora do núcleo);
- revisão adversarial sem finding crítico/alto aberto.

## Não objetivos

- reimplementar adapter Cursor (FEATURE-098);
- repetir smoke de manifesto da 099;
- failover Cursor↔OpenCode em gate 0/auth (FEATURE-094 escopo distinto);
- auth multi-usuário ou multi-checkout no cockpit;
- promover Hermes (`BL-0001`).

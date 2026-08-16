# HND-2026-0013 — Pedido de adapter Cursor (backlog BL-0004)

- Documento: HND-2026-0013
- Origem: agente em `cursor-ralph-profile` (perfil Cursor; plugin 1:1 do bc-harness)
- Destino: `ralph-method` (repositório principal)
- Pedido: HO-2026-08-16-001
- Estado: **registrado no backlog como BL-0004** (adiado) — sem implementação autorizada sem ADR + PRD + critérios
- Política de conhecimento: non_blocking

## Pedido (resumo executivo)

Promover a CLI Cursor (`agent` / `cursor-agent`) a quarto adapter executável do
Ralph Method, no mesmo rito do agy (FEATURE-095 / ADR-0017): schema
`runner-result` `1.2.0` com runner `cursor`, detector/probe não generativo no
`ralph-init`, adapter na seam `preflight|run|version`, perfil
`.ralph/cursor.env`, loop `--engine cursor`, fixtures offline e documentação
sincronizada.

Decisões de contrato v1 (não negociar em silêncio):

- `schema_version` `1.2.0`, runner `cursor`, terminal de sucesso `result`
  (stream-json do Cursor);
- verify v1: `agent -p --mode ask` — `permission_policy_status=declared` e
  `permission_policy_hash=null` (nunca `verified` sem prova mecânica
  equivalente à do OpenCode);
- `verification_agent` literal `ask`; fallback `none`;
- prompt por arquivo (SHA-256, ≤256 KiB); stream 5 MiB / 10k eventos / 30 min;
- identidade canônica `cursor` (não `cursor-agent` como provider separado);
- CLI aceita `agent` ou `cursor-agent`; rodar por bash (WSL/Git Bash no Windows).

Fora de escopo (fail-closed): alterar máquina de estados/lease/fencing do
`ralph-control`, fallback automático Cursor↔outros providers, persistir
`CURSOR_API_KEY`, portar o plugin bc-harness para dentro do método, promover
Hermes, tratar `/loop` do Cursor IDE como `ralph-control`.

## Status no ralph-method

- Item adicionado ao [`docs/backlog.md`](../../docs/backlog.md) como `BL-0004`
  (prioridade P1, adiado).
- A implementação só entra no roadmap ativo após: ADR novo (próximo livre;
  sugerido ADR-0021 — o ADR-0020 é migração por origem, já usado) + PRD em
  `docs/prd/prd-adapter-cursor.md` + SPEC/PLAN/PHASES em
  `.spec/features/098-cursor-adapter/` + fixtures offline + campo opt-in.
- Regra do backlog: não autoriza implementação automática.

## Próximo passo no perfil Cursor (quando o adapter oficial existir)

1. Alinhar `cursor-ralph-profile/adapters/cursor` ao contrato oficial (PHP,
   schema promovido);
2. apontar `.ralph/cursor.env` para o runner instalado pelo método;
3. não manter schema `1.2.0` paralelo se o oficial já existir;
4. só então tratar o loop unattended Cursor como certificado.

## Bloqueios

Nenhum. O pedido está registrado e aguarda decisão de reabrir como FEATURE-098.

# Backlog do Ralph Method

Itens adiados conscientemente, sem prioridade nesta linha de desenvolvimento.

| ID | Item | Prioridade | Status | Condição para reabrir |
|---|---|---|---|---|
| `BL-0001` | Adapter de execução Hermes | nenhuma | adiado | necessidade explícita de orquestrar Hermes como harness filho |
| `BL-0002` | Adapter de execução agy | P0 | promovido na v0.9.0 | reaberto pela FEATURE-095 e ADR-0017; entregue e publicado com o relatório `0025` |
| `BL-0003` | Regressão multiprovider Hermes/agy | P0 para agy | parcialmente entregue | `agy` entrou na regressão e foi promovido; Hermes permanece adiado até possuir adapter aprovado |
| `BL-0004` | Adapter de execução Cursor (CLI `agent`/`cursor-agent`) | P1 | entregue na FEATURE-098 (ADR-0021 + PRD + schema 1.2.0 + adapter na seam + fixtures offline) | aguardando campo opt-in e revisão adversarial antes da promoção |

## Handoff Cursor (HO-2026-08-16-001)

Origem: agente em `cursor-ralph-profile` (perfil Cursor com plugin 1:1 do
bc-harness). Pedido: promover a CLI Cursor (`agent`/`cursor-agent`) a quarto
adapter executável do Ralph Method (runner `cursor`, schema `1.2.0`, verify v1
`--mode ask` com `permission_policy_status=declared` — nunca `verified` nesta
v1), no mesmo rito do agy (FEATURE-095 / ADR-0017).

**Cursor é uma IDE com LLM embutido, sem API_KEY:** a autenticação é a sessão
local da conta Cursor (login do operador), não uma chave própria. O detector do
`ralph-init` NÃO procura `CURSOR_API_KEY`; presença da CLI + sessão autenticada
(`agent status --format json`) é a autoridade. O modelo vem da sessão/workspace
do editor (o perfil pode fixar o modelo, mas auth é da sessão). Nenhum
`CURSOR_API_KEY` em arquivo versionado.

Não implementar sem: ADR novo + PRD + critérios + fixtures offline + campo
opt-in. Fora de escopo: alterar autoridade do control plane, fallback automático
Cursor↔outros, persistir `CURSOR_API_KEY`, portar o plugin bc-harness, promover
Hermes, tratar `/loop` do Cursor IDE como `ralph-control`.

## Regra do backlog

O backlog não autoriza implementação automática. Um item somente entra no
roadmap ativo após decisão explícita, atualização do ADR correspondente e
definição de critérios de aceitação, evidências e gates.

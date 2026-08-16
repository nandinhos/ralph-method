# ADR-0021 — Adapter Cursor (IDE com LLM embutido, runner declarado)

- **Status:** accepted
- **Date:** `2026-08-16`
- **Owner:** Equipe do Ralph Method

## Contexto

O Cursor é uma **IDE com LLMs embutidos**, não um serviço de API com chave
própria. Sua autenticação é a **sessão local da conta Cursor** (login do
operador no editor/CLI headless `agent`/`cursor-agent`), nunca uma
`CURSOR_API_KEY`. O Cursor possui CLI própria (headless), instalada separada
do editor (`irm 'https://cursor.com/install?win32=true' | iex` no Windows); no
Windows a CLI roda no PowerShell e o runner do método continua bash (Git Bash
ou WSL). O Cursor já possui um perfil com plugin 1:1 do `bc-harness`
(`cursor-ralph-profile`) e a CLI headless que emite `stream-json`, o que o
torna candidato a runner executável do Ralph Method no mesmo rito do agy
(FEATURE-095 / ADR-0017).

O handoff HO-2026-08-16-001 pede a promoção do Cursor a quinto runner
executável. Este ADR reabre o escopo de harnesses (ADR-0007) para incluir o
Cursor como adapter, sem alterar a autoridade do control plane nem permitir
fallback automático.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Manter Cursor fora do método** | superfície mínima | perfil Cursor já existe; perde runner comprovado |
| **B — Adapter executável na seam** | reutiliza o mesmo rito de opencode/agy | exige schema 1.2.0, fixtures e docs; verify v1 limitado |
| **C — Fallback automático Cursor↔outros** | aparente continuidade | viola exclusividade e fail-closed; rejeitado |

## Decisão

Adotar a opção B: **runner `cursor`** como quinto runner executável, com
contrato `runner-result` `1.2.0` e **verify v1 declarado** (`--mode ask`,
`permission_policy_status=declared`, `permission_policy_hash=null` — nunca
`verified` sem prova mecânica equivalente à do OpenCode). Fallback permanece
`none`. A autenticação é a **sessão local da conta Cursor**; o detector do
`ralph-init` **não procura API_KEY** — presença da CLI + sessão autenticada
(`agent status --format json`) é a autoridade.

## Consequências

### Positivas

- Cursor vira runner real com o mesmo contrato sanitizado dos demais;
- sem reduzir gates, identidade ou ausência de fallback silencioso;
- `--mode ask` nunca é tratado como policy proof mecânica.

### Negativas

- verify v1 é `declared`, não `verified`: o operador sabe que não há isolamento
  mecânico nesta versão;
- o adapter deve ser executado via bash (WSL/Git Bash no Windows);
- a CLI `agent`/`cursor-agent` é aceita; a identidade canônica permanece
  `cursor`.

### Obrigações

- nenhum `CURSOR_API_KEY` em arquivo versionado (auth é sessão local);
- nenhum fallback automático Cursor↔Codex/Claude/OpenCode/agy;
- nenhuma promoção sem fixtures offline, regressão completa e campo opt-in
  (`field_certification` explícito no relatório);
- `permission_policy_status=verified` exige prova mecânica — fora desta v1.

## Gatilho para revisitar

Revisitar quando o Cursor expuser prova mecânica de política read-only
equivalente à do OpenCode, permitindo elevar o verify de `declared` para
`verified`.

# Adapter `cursor` para o Ralph Method

> **Versão**: 1.0.0
> **Status**: Aprovado para implementação
> **Criado em**: 2026-08-16
> **Autor**: Ralph Method (a partir do HO-2026-08-16-001)

---

## Tese do produto

> Tornar a CLI Cursor (`agent`/`cursor-agent`) um runner executável do Ralph
> Method sem reduzir gates, identidade, ausência de fallback silencioso e sem
> fingir que `--mode ask` é policy proof mecânica.

O Cursor é uma **IDE com LLM embutido**: a autenticação é a sessão local da
conta Cursor, não uma API key. O detector do `ralph-init` não procura
`CURSOR_API_KEY`; a presença da CLI + sessão autenticada
(`agent status --format json`) é a autoridade.

## Hero Flow

Um mantenedor instala o Ralph Method, solicita a verificação explícita do
provider `cursor`, recebe readiness funcional somente quando CLI + sessão +
modelo estão comprovados, e executa uma fase. O `cursor` implementa em uma
sessão headless (`agent -p --force --trust --output-format stream-json`) e
revisa em sessão `--mode ask` (sem `--force`, `permission_policy_status`
declarado). O loop aceita a fase apenas após resultado normalizado 1.2.0 e
gates externos verdes.

## 1. Problema

### O problema

O Ralph detecta a CLI Cursor mas a rejeita (runner enum só opencode/agy). Não
há caminho de execução, perfil instalável nem fixture. Uma integração ingênua
poderia tratar `--mode ask` como prova de política ou confundir o terminal
`result` do Cursor.

### Solução atual e limitações

Sem adapter: o Cursor fica fora do método, e o perfil `cursor-ralph-profile`
mantém um parser paralelo não oficial.

## 2. Público-alvo e contexto

Mantenedores que já têm sessão Cursor autenticada e querem rodar o mesmo loop
determinístico. Windows: runner oficial é bash (WSL/Git Bash); sem PowerShell
nesta v1.

## 3. Critérios P0 (não negociáveis)

- [x] P0.1 — readiness não generativo: `agent status --format json` e
  `agent models`; zero geração no probe.
- [x] P0.2 — adapter fail-closed na seam `preflight|run|version`, parser PHP
  normaliza `stream-json` para `runner-result` 1.2.0.
- [x] P0.3 — verify v1 `declared`: `--mode ask`, `permission_policy_status`
  sempre `declared`, hash `null`, `verification_agent=ask`.
- [x] P0.4 — perfil `.ralph/cursor.env` sem `CURSOR_API_KEY`; fallback `none`;
  identidade canônica `cursor`.

## 4. Contrato 1.2.0

| Campo | Valor v1 |
|---|---|
| `schema_version` | `1.2.0` |
| `runner` | `cursor` |
| terminal de sucesso | `result` (stream-json do Cursor) |
| `identity_status` | `observed` se model no init; senão `declared` |
| verify | `--mode ask` sem `--force` |
| `permission_policy_status` (verify) | `declared` — nunca `verified` |
| `permission_policy_hash` (verify) | `null` |
| `verification_agent` | `ask` |
| `fallback` | `none` |
| prompt | arquivo, SHA-256, ≤256 KiB |
| stream | 5 MiB / 10k eventos / 30 min |

Proibido no contrato inicial: `--continue`, `--resume`, `--fork`, stdin de
prompt, sessão reutilizada, ferramenta de escrita observada em verify.

## 5. Decisões de produto

- CLI aceita `agent` ou `cursor-agent`; identidade canônica `cursor`.
- Sem API key: auth é sessão local.
- Ordem auto determinística: Cursor inserido depois de agy (último adapter
  novo); nunca escolher Cursor por preferência do operador.
- `--mode ask` é convenção de modo, não fingerprint de política.

## 6. Fora de escopo (fail-closed)

- alterar máquina de estados, lease, fencing ou autoridade de `ralph-control`;
- fallback automático Cursor ↔ Codex/Claude/OpenCode/agy;
- declarar `permission_policy_status=verified` sem prova mecânica;
- persistir prompt, resposta completa, `CURSOR_API_KEY` ou credencial;
- portar o plugin bc-harness para dentro do método;
- promover Hermes;
- tratar `/loop` do Cursor IDE como `ralph-control`.

## 7. Arquitetura

- `adapters/cursor/` (runner.sh, parser.php, contract.md) na seam comum;
- `bin/ralph-init` detecta `agent`/`cursor-agent`, probe `status`/`models`;
- `scripts/ralph.sh --engine cursor` despacha pela mesma interface;
- `bin/ralph-control` importa `runner-result` 1.2.0 (gate 0 lê o contrato).

## 8. Riscos

| Risco | Mitigação |
|---|---|
| `--mode ask` permitir write | parser reprova `writeToolCall`; canário de arquivo; status `declared` |
| CLI `agent` vs `cursor-agent` | aceitar os dois; identidade `cursor` |
| Probe generativo acidental | readiness só `status` e `models` |
| Schema quebrar agy/opencode | `allOf` por versão; fixtures antigas no CI |
| Windows sem bash | documentar WSL/Git Bash; CI Linux |
| Supervise limpar `RALPH_CURSOR_*` | mesma lição do OpenCode; documentar no AGENT_GUIDE |

## 9. Métricas de sucesso

- `ralph-init plan --provider cursor --verify-providers` com fake CLI
  autenticada → `functional` + `adapter_enabled=true`;
- sem CLI/sem auth/sem modelo → `needs_review` ou `adapter_enabled=false`;
- `scripts/ralph.sh --engine cursor` completa gate 0 com `runner=cursor` 1.2.0;
- fixtures 1.0.0 (opencode) e 1.1.0 (agy) continuam verdes;
- verify que escreve arquivo falha o parser;
- `check-doc-sync.sh` + CI portátil verdes.

## 10. Campo

Opt-in, fora da CI: uma fase impl + uma verify `ask` sanitizada. Sem isso, a
feature fecha contratos + fixture, mas o relatório marca
`field_certification=pending` — não promove VERSION como "certificado em campo"
sem evidência.

## 11. Nomes e identificadores

- Feature: `FEATURE-098-CURSOR-ADAPTER`
- ADR: `0021-adapter-cursor`
- PRD: `docs/prd/prd-adapter-cursor.md`
- Perfil: `.ralph/cursor.env`
- Runner: `cursor`

## 12. Critérios de aceite

- `ralph-init plan --project <fixture> --provider cursor --verify-providers`
  com fake CLI autenticada retorna `functional` e, com adapter+modelo,
  `adapter_enabled=true`;
- sem CLI/sem auth/sem modelo → `needs_review` ou `adapter_enabled=false`,
  nunca execução;
- `--provider auto` não escolhe Cursor por preferência; ordem determinística;
  fallback `none`;
- `scripts/ralph.sh --engine cursor` numa fixture com fake agent completa gate 0
  com `runner=cursor` `schema_version=1.2.0`;
- fixtures 1.0.0 (opencode) e 1.1.0 (agy) continuam verdes;
- verify que escreve arquivo falha o parser/resultado;
- nenhum `CURSOR_API_KEY` em arquivo versionado;
- `check-doc-sync.sh` + CI portátil verdes;
- `AGENT_GUIDE` lista Cursor na tabela de decisão;
- handoff de conclusão escrito e sem segredos.

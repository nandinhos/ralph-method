# Integrações condicionais de harnesses e providers

O Ralph Method possui cinco harnesses executáveis nesta linha. A tabela
abaixo distingue runners nativos, adapters dedicados e detecção passiva:

| Harness | Implementação atual | Estado |
|---|---|---|
| Codex | runner nativo em `scripts/ralph.sh` | certificado no loop |
| Claude CLI | runner nativo em `scripts/ralph.sh` | certificado no loop |
| OpenCode | adapter explícito em `adapters/opencode/` | certificado em campo |
| Hermes | readiness passiva | backlog, prioridade nenhuma |
| agy | adapter explícito em `adapters/agy/` | candidato funcional; verify Linux allowlisted |
| Cursor | adapter explícito em `adapters/cursor/` | candidato funcional; verify v1 declarado (ask) |

No contrato técnico, OpenCode, `agy` e Cursor possuem diretórios de adapter
dedicados; Codex e Claude são runners nativos do loop. Todos passam pelo mesmo
contrato de trace e gates, sem receber autoridade do controlador.

Um adapter só pode ser habilitado quando o instalador registrar o provider
como `functional` e com `runner_supported=true` em `.ralph/providers.json`. A
presença do executável, autenticação isolada ou uma versão conhecida não são
suficientes.

O fluxo mínimo é:

```text
detected
→ authentication check
→ safe diagnostic
→ functional
→ runner suportado
→ adapter_enabled=true
```

Os probes da primeira versão são explícitos, curtos e não generativos:

```bash
bin/ralph-init plan --project /caminho/do/projeto --verify-providers
```

Eles não iniciam uma conversa, não enviam prompt e não fazem probe remoto de
geração. O status `functional` significa que a CLI local confirmou a sessão e
seu diagnóstico seguro. Ele pode existir sem `adapter_enabled` enquanto o
runner do Ralph ainda não estiver implementado; uma prova de inferência real é
uma política futura, opt-in e separada.

Nenhum adapter ou runner pode gravar ledger, alterar gates, trocar provider
silenciosamente ou salvar credenciais. O contrato compartilhado está em
`schemas/provider-readiness.schema.json`.

## Adapter OpenCode

O primeiro adapter executável está em `adapters/opencode/`. Ele usa
`opencode run --format json` com modelo explícito, transporte de prompt por
`--file`, parser fail-closed e resultado em
`schemas/runner-result.schema.json`. A execução deve ocorrer pelo
`ralph-control`; chamar o runner isoladamente é apenas um teste de contrato e
não libera feature nem gate.

## Adapter agy

O adapter em `adapters/agy/` implementa a mesma seam
`preflight|run|version`, usa `agy --output-format stream-json` e publica
`runner-result 1.1.0` com terminal `result`. Implementação usa permissões de
mutação explícitas; verificação exige Linux, `bwrap`, agente `ralph-review`,
app-data efêmero e montagem read-only do token OAuth e de `repo-root`.

`--mode plan` é somente defesa em profundidade: a fronteira preventiva é o
namespace allowlisted. O parser reprova ferramentas fora da allowlist,
divergência de modelo, múltiplas conversas ou terminais e qualquer política
incompleta. A prova direta isolada pode ser repetida com
`bash scripts/test-agy-field.sh`; ela exige sessão local autenticada e não faz
parte da CI sem credenciais.

## Adapter Cursor

O adapter em `adapters/cursor/` implementa a mesma seam `preflight|run|version`
e publica `runner-result 1.2.0` com terminal `result`. O Cursor é uma IDE com
LLM embutido: a autenticação é a sessão local da conta (sem API key), e a CLI
pode aparecer como `cursor-agent` ou `agent`. O modelo é sempre explícito via
`RALPH_CURSOR_MODEL` (sem default).

A verificação v1 é declarada: `verify --mode ask`, com
`permission_policy_status=declared`, `permission_policy_hash=null` e
`verification_agent=ask`. Ela nunca é uma prova read-only com hash — `verified`
é proibido nesta versão e o parser reprova qualquer escrita observada em modo
verify. O parser normaliza `--output-format stream-json` e falha fechado em
JSONL inválido, zero eventos, múltiplos eventos `result`, modelo divergente e
escrita em verify, além de sanitizar eventos persistidos.

# Integrações condicionais de harnesses e providers

A release `0.4.0` fecha o escopo operacional em três harnesses. A tabela
abaixo distingue o que já é executável do que é apenas uma integração nativa
ou detecção passiva:

| Harness | Implementação atual | Estado |
|---|---|---|
| Codex | runner nativo em `scripts/ralph.sh` | certificado no loop |
| Claude CLI | runner nativo em `scripts/ralph.sh` | certificado no loop |
| OpenCode | adapter explícito em `adapters/opencode/` | certificado em campo |
| Hermes | readiness passiva | backlog, prioridade nenhuma |
| agy | readiness passiva quando detectável | backlog, prioridade nenhuma |

“Três adapters” é uma abreviação operacional. No contrato técnico, somente
OpenCode possui hoje um diretório de adapter dedicado; Codex e Claude são
runners nativos do loop e passam pelo mesmo contrato de trace e gates.

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

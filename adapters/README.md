# Adaptadores condicionais de providers

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

Nenhum adapter pode gravar ledger, alterar gates, trocar provider silenciosamente
ou salvar credenciais. O contrato compartilhado está em
`schemas/provider-readiness.schema.json`.

## Adapter OpenCode

O primeiro adapter executável está em `adapters/opencode/`. Ele usa
`opencode run --format json` com modelo explícito, transporte de prompt por
`--file`, parser fail-closed e resultado em
`schemas/runner-result.schema.json`. A execução deve ocorrer pelo
`ralph-control`; chamar o runner isoladamente é apenas um teste de contrato e
não libera feature nem gate.

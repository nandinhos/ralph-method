# Modelo de dados do Ralph Method

## Ownership

| Dado | Local | Dono |
|---|---|---|
| workflow versionado | `.ralph/workflow.json` | projeto-alvo |
| configuração do método | `.ralph/method.json` | instalação local |
| capabilities/providers | `.ralph/providers.json` | instalador/usuário |
| eventos e locks | `.git/ralph-control/` | `ralph-control` |
| handoffs | `.ralph/handoffs/` | controlador e projeto |
| memória curada | `docs/engineering/` | projeto-alvo |
| manifesto de instalação | `.ralph/install-manifest.json` | `ralph-init` |
| relatório de remoção | `.ralph/uninstall-report.json` | `ralph-init` |
| feedback do loop | `.git/ralph-control/feedback/events.jsonl` | `ralph.sh` |
| perfis de execução | `.ralph/codex.env`, `.ralph/claude.env` | instalador/usuário |

## Regras

- o ledger é JSONL append-only com hash chain;
- leases em claro não entram no ledger;
- tokens, prompts e custos não entram em eventos;
- relatório `TRC` é projeção do ledger e não fonte de estado;
- o manifesto de instalação registra versão e hashes, não segredos.
- feedback é telemetria operacional local, não é fonte de transição;
- o uninstall respeita hashes e preserva qualquer arquivo que o usuário tenha
  alterado depois da instalação.

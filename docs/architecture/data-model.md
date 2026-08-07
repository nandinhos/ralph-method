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

## Regras

- o ledger é JSONL append-only com hash chain;
- leases em claro não entram no ledger;
- tokens, prompts e custos não entram em eventos;
- relatório `TRC` é projeção do ledger e não fonte de estado;
- o manifesto de instalação registra versão e hashes, não segredos.

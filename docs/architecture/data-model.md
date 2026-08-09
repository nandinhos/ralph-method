# Modelo de dados do Ralph Method

## Ownership

| Dado | Local | Dono |
|---|---|---|
| manifesto de workflow versionado | caminho informado em `ralph-control init --manifest` | projeto-alvo |
| workflow ativo | `.git/ralph-control/workflow.json` | `ralph-control` |
| configuração do método | `.ralph/method.json` | instalação local |
| capabilities/providers | `.ralph/providers.json` | instalador/usuário, com prontidão verificada |
| eventos e locks | `.git/ralph-control/` | `ralph-control` |
| exclusividade de execução | `.git/ralph-control/executions/<sha256>.lock` | `ralph-control`, mantido durante o bloco |
| handoffs | `.ralph/handoffs/` | controlador e projeto |
| memória curada | `docs/engineering/` | projeto-alvo |
| manifesto de instalação | `.ralph/install-manifest.json` | `ralph-init` |
| relatório de remoção | `.ralph/uninstall-report.json` | `ralph-init` |
| lock de instalação | `.ralph/install.lock` | `ralph-init`, preservado para coordenação local |
| feedback do loop | `.git/ralph-control/feedback/events.jsonl` | `ralph.sh` |
| métricas derivadas | stdout de `bin/ralph-metrics` | consumidor do projeto/orquestrador, sem persistência implícita |
| perfis de execução | `.ralph/codex.env`, `.ralph/claude.env` | instalador/usuário |

## Regras

- o ledger é JSONL append-only com hash chain;
- toda escrita no ledger passa pelo `workflow.lock`; chamadas aninhadas ao
  controlador reutilizam a mesma posse lógica do lock;
- o lock de execução por feature é mantido enquanto o processo controlado e
  seus filhos estão vivos; sua liberação ocorre no encerramento do processo;
- leases em claro não entram no ledger;
- tokens, prompts e custos não entram em eventos;
- relatório `TRC` é projeção do ledger e não fonte de estado;
- o manifesto de instalação registra versão e hashes, não segredos.
- `.ralph/providers.json` registra somente path, versão, capacidades, status,
  suporte do runner, provider-alvo, códigos de saída e timestamps dos probes;
  não registra saída bruta,
  credenciais, tokens ou prompts.
- `adapter_enabled` só pode ser verdadeiro quando `status` é `functional` e
  `runner_supported` é verdadeiro.
- `functional` nesta versão significa autenticação confirmada e diagnóstico
  local não generativo aprovado para a CLI; não significa probe real de
  geração.
- feedback é telemetria operacional local, não é fonte de transição;
- métricas são uma projeção descartável do ledger: a execução não cria,
  reescreve ou repara eventos e não mede custo/token;
- o uninstall respeita hashes e preserva qualquer arquivo que o usuário tenha
  alterado depois da instalação.

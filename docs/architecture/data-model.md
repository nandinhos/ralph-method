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
| candidatos de memória | `.ralph/knowledge-candidates/` | controlador e curador; cache sanitizado e descartável |
| memória curada | `docs/engineering/` | projeto-alvo |
| manifesto de instalação | `.ralph/install-manifest.json` | `ralph-init` |
| detecção de instalação | saída transitória de `ralph-init plan` | `ralph-init`, sem persistência implícita |
| relatório de remoção | `.ralph/uninstall-report.json` | `ralph-init` |
| estado de evolução | `.ralph/evolutions/EVL-YYYYMMDD-NNNN/evolution.json` | `ralph-init evolve/rollback` |
| backup de evolução | `.ralph/evolutions/<evolution_id>/backup/` | `ralph-init`, com hashes e sem importação de estado |
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
- a detecção de Ralph externo registra somente estado, caminhos relativos,
  tipos e SHA-256; não persiste conteúdo de configuração, prompts ou ledger.
- backup e rollback de uma instalação externa exigirão manifesto próprio,
  hashes antes/depois e confirmação explícita; não são efeito colateral do
  `apply` comum. A evolução implementada usa o modo `quarantine_only`: move
  somente sinais detectados, preserva ledger/workflow e instala o método novo
  com aceite pendente.
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
- candidatos de memória não são conhecimento validado: contêm apenas origem,
  status e decisão de retenção; a publicação exige a ação explícita `curated`;
- `docs/engineering/INDEX.md` é o índice macro e `categories/` e `topics/` são
  projeções regeneráveis, não fontes independentes de verdade;
- taxonomia de lição usa `category`, `topics`, `stack`, `domain` e
  `fingerprints`; filtros estruturados reduzem o conjunto antes da recuperação
  lexical e do limite de contexto;
- `knowledge_policy.mode` controla continuidade e permanece `non_blocking`;
  retenção (`persist`, `discard` ou revisão) é uma decisão separada;
- rejeitar ou descartar uma memória não apaga o handoff, as evidências ou os
  eventos do ledger.

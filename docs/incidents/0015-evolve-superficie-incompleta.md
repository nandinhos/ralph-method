# Incidente 0015 — Evolução deixava conflitos fora da quarentena

## Sintoma

O dry-run de `ralph-init evolve` reconhecia `bin/ralph-control`,
`bin/ralph-block` e o runtime em `.git/ralph-control/`, mas marcava outros
arquivos Ralph existentes como `conflict`. O `--apply` poderia mover os dois
binários detectados e só então falhar ao encontrar um conflito adicional.

## Causa raiz

O detector enumerava somente alguns sinais fortes de uma instalação externa.
O instalador, entretanto, gerencia uma superfície maior: monitor, trace,
bloco, hook, scripts auxiliares, schemas, adapters e perfis gerados. A etapa de
planejamento da evolução só convertia `conflict` em
`quarantine_then_create` quando o caminho estava na lista de sinais detectados;
os demais arquivos ficavam fora do backup e bloqueavam a publicação.

## Correção

Quando não existe manifesto do Ralph Method, a detecção passa a acrescentar à
lista de sinais os arquivos existentes da superfície declarada por
`managedSources()` e `generatedPaths()`. O tipo identifica arquivos gerenciados
ou perfis gerados, sem ler conteúdo para formar a decisão. Os caminhos de
runtime `.git/ralph-control/events.jsonl` e `workflow.json` continuam tratados
separadamente: permanecem no lugar, têm seus hashes registrados e não são
importados.

O `apply` comum continua bloqueado para qualquer instalação externa. Somente
`evolve --apply` pode quarentenar os sinais, instalar de forma transacional e
deixar o estado em `awaiting_acceptance`.

## Evidência

- `bash scripts/test-installation.sh` — fixture completa de superfície,
  backup dos conflitos, instalação em estado de aceite e preservação dos
  hashes de ledger/workflow.
- `bash scripts/check-shell.sh` — sintaxe dos scripts preservada.

## Risco residual

Arquivos Ralph externos que não usam nomes da superfície gerenciada continuam
dependendo de detecção explícita ou de um detector futuro de assinatura. O modo
`quarantine_only` não importa semântica de ledger, workflow, prompts ou
credenciais.

## Prevenção

Qualquer novo arquivo gerenciado pelo método deve entrar em `managedSources()`
ou `generatedPaths()` e na fixture de instalação/evolução correspondente.

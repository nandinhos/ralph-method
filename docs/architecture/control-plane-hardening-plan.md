# Plano de hardening do control plane — v0.5.0

Este documento é o contrato de execução da evolução iniciada em
`feat/ralph-hardening`. Ele separa a barreira crítica de concorrência das
melhorias posteriores e define quando cada etapa pode ser promovida.

## Princípio de promoção

Uma etapa só avança quando o código, a regressão portátil, a evidência do
cenário adversarial e a documentação correspondente estiverem verdes. Um
check verde de sintaxe não aprova uma garantia de estado; cada garantia precisa
de um teste que reproduza a pane ou a corrida que ela pretende impedir.

## Fases

| Fase | Objetivo | Critério de saída | Estado |
|---|---|---|---|
| 0A | Exclusividade por `workflow_id + feature_key` | segunda execução, alias de workflow e transição concorrente bloqueados | concluída no checkpoint `bfc426a`, correções adversariais em andamento |
| 0B | Crash, fencing e retomada segura | controlador morto não permite replay; `continue` encaminha a `recovery_required`; `retry` cria novo fencing token | concluída nesta branch, aguardando regressão final |
| 0C | Integridade do ledger | append concorrente serializado; inicialização atômica; repair de corrupção terminal preservado | parcial; ampliar cobertura de `repair-ledger` |
| 1 | Handoff e conhecimento não bloqueante | entrega liberada sem curadoria; curadoria idempotente; lição validada e recuperação seletiva | próxima |
| 2 | Documentação e release | STATUS, ADR, incidentes, changelog, versão e tags coerentes | pendente |
| 3 | CI portátil | checks oficiais reproduzidos em ambiente limpo a cada alteração | pendente |
| 4 | Métricas read-only | agregados históricos sem mutar ledger ou estado | pendente |
| 5 | DX e escala opcional | diff preview, exemplos e extensões só se houver benefício comprovado | pendente |

## Contratos da Fase 0

1. O `workflow_id` recebido precisa ser exatamente o ID do `workflow.json`
   local.
2. A chave de execução é derivada do ID canônico carregado e da feature.
3. `run`, `start`, `finish` e `reconcile` não podem ocupar a mesma feature ao
   mesmo tempo.
4. `appendEvent()` lê o último hash e acrescenta a linha sob `workflow.lock`.
5. A tentativa que possui `attempt.started` sem `block.finished` não pode ser
   repetida com o mesmo lease depois que não há processo ativo.
6. A recuperação é explícita: `recovery_required` → `recover` → `retry` → novo
   `attempt` e novo fencing token.
7. `verify` prova integridade criptográfica e schema; a validade das transições
   é uma responsabilidade adicional dos testes de projeção.

## Cenários mínimos da regressão

- duas execuções com mesmo workflow e feature;
- mesma feature com workflow alternativo;
- `finish` durante um `run` ativo;
- morte do controlador com filho vivo;
- replay depois que o filho termina;
- `continue`/`supervise` encaminhando a recovery;
- retry com lease anterior rejeitado e novo fencing aceito;
- append concorrente e cadeia de hash íntegra;
- criação concorrente de ledger sem truncamento;
- repair de corrupção somente no final, com backup e relatório.

## Limites deliberados

Esta fase não cria execução paralela de features, múltiplos workflows no mesmo
checkout, locks distribuídos ou um banco de coordenação. Esses cenários têm
gatilhos de revisão próprios e não devem ser inferidos a partir do lock local.

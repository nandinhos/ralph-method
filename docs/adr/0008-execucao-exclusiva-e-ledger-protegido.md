# ADR 0008 — Execução exclusiva por feature e ledger protegido

## Status

Aceita para a evolução `feat/ralph-hardening`.

## Contexto

O control plane já possuía `workflow.lock` para mutações curtas, mas o bloco
controlado permanece executando por vários segundos ou minutos fora desse lock.
O caminho `ralph-control run` podia aceitar duas chamadas com o mesmo lease e
iniciar dois processos para a mesma feature. Além disso, `appendEvent()` podia
ser chamado por um caminho que não tivesse adquirido explicitamente o lock.

Isso ameaçava a regra de uma feature por bloco e podia fazer duas chamadas
calcularem o mesmo `prev_event_hash`, comprometendo a hash chain do ledger.

## Decisão

O `ralph-control` adota duas proteções locais:

1. Cada `workflow_id + feature_key` possui um lock exclusivo em
   `.git/ralph-control/executions/`. O lock é adquirido antes do início do
   processo controlado e permanece retido até seu encerramento.
2. `appendEvent()` adquire `workflow.lock` antes de ler o último evento,
   calcular o hash e anexar a linha. Chamadas internas reutilizam a posse
   lógica já adquirida para não criar deadlock em operações compostas.

Depois de adquirir o lock de execução, o controlador recarrega o workflow,
revalida o lease e confirma que a feature ainda está em `running`. Uma segunda
execução falha com exit `12`, sem iniciar provider, processo ou transição.

## Consequências

- a regra de uma execução por feature passa a ter uma barreira operacional;
- o `workflow.lock` continua curto e não é retido durante o agente;
- o ledger fica protegido mesmo quando um novo caminho esquece de envolver a
  chamada explicitamente;
- locks abandonados são liberados pelo sistema operacional quando o processo
  termina, inclusive por crash;
- features diferentes continuam serializadas pela fila atual; não foi criado
  suporte a múltiplos workflows ou execução paralela entre features;
- a recuperação de corrupção intermediária continua fail-closed.

## Evidência

O teste `scripts/test-ralph-method.sh` reproduz duas chamadas simultâneas para
a mesma feature. A primeira conclui; a segunda recebe exit `12`; o ledger passa
por `ralph-control verify` e possui uma única ocorrência de `attempt.started`,
`command.started` e `block.finished`.

## Gatilho para revisitar

Revisitar esta decisão se o método passar a suportar múltiplos workflows no
mesmo checkout, execução paralela entre features ou um controlador remoto. Esse
cenário exigirá um modelo explícito de ownership, namespace de locks e
recuperação distribuída; não deve ser inferido a partir deste lock local.

## Data

2026-08-09.

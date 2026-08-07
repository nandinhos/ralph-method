# Incidente 0001 — Probe de provider podia aguardar processo filho

## Sintoma

O fixture de prontidão simulou um provider que permanecia em execução durante
o diagnóstico. O timeout manual interrompia o processo principal, mas o comando
de captura ainda podia aguardar um processo filho que mantinha os pipes abertos.

## Causa raiz

`proc_open` executava um shell intermediário. A primeira implementação usava
`proc_terminate` somente no processo observado; isso não garantia a
finalização de descendentes antes de `proc_close` retornar.

## Correção

`bin/ralph-init::commandResult` passou a envolver probes com o utilitário
`timeout` quando disponível, enviando `TERM` e depois `KILL` após uma janela
curta. O caminho sem esse utilitário mantém o timeout manual como fallback.
Saída, códigos e marcação `timed_out` continuam sanitizados e não são
persistidos como saída bruta do provider.

## Prevenção

`scripts/test-provider-readiness.sh` contém um provider falso que dorme por
mais tempo que o limite e verifica que o plano retorna antes de doze segundos,
sem habilitar o adapter. A regressão deve permanecer junto do contrato de
prontidão.

## Evidência

- arquivo corrigido: `bin/ralph-init`, função `commandResult`;
- teste: `bash scripts/test-provider-readiness.sh`;
- status esperado: provider em `authentication_unknown` e
  `adapter_enabled=false`;
- sem execução de prompt ou geração.

## Risco residual

Ambientes sem um utilitário `timeout` dependem do fallback de `proc_terminate`;
providers que criem árvores de processos complexas podem exigir um adapter
específico com controle de grupo de processos antes de qualquer probe novo.

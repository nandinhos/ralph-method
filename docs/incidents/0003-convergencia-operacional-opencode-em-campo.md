# Incidente 0003 — convergência operacional do OpenCode em campo

## Sintoma

As duas primeiras tentativas do campo real não chegaram a um resultado
terminal importável pelo Ralph. Em uma delas, a sessão iniciou verificações
auxiliares de `bin/check` e entrou em ciclo operacional; em outra, o modelo
alterou a feature, mas excedeu o limite de 300 segundos sem emitir o evento
terminal.

## Causa raiz

Disponibilidade da CLI e saída JSON não garantem convergência de uma sessão
generativa. O modelo gratuito inicialmente selecionado não respeitou o limite
operacional de forma determinística e iniciou atividades concorrentes que
competiam com o portão síncrono do loop.

## Correção

O systematic debugging confirmou as hipóteses sem alterar a árvore. A
execução foi retomada em checkout limpo, com permissões granulares para
impedir `nohup`, `sleep` e verificações concorrentes, timeout explícito,
contenção de processos e seleção alternativa do modelo `opencode/big-pickle`.
O controlador continuou exigindo exatamente um resultado `impl` e um
resultado `verify`, ambos com evento terminal.

## Prevenção

- timeout e contenção continuam obrigatórios no adapter;
- processos residuais são causa de recovery, nunca de aprovação;
- retry não reaproveita árvore suja como se fosse resultado verde;
- o modelo solicitado permanece com identidade `declared` quando o provider
  não comprova o modelo efetivo;
- somente `ralph-control` pode abrir gates, aprovar, liberar e avançar.

## Evidência

O workflow final de campo `wf_field_refactor_radar_20260808_004` terminou com
duas delegações OpenCode normativas, `bin/check` verde, cinco gates aprovados,
handoff versionado e nenhum processo residual. Os diagnósticos locais das
tentativas anteriores foram `DBG-2026-0001` e `DBG-2026-0002` dentro dos
ledgers descartáveis das checkouts de campo.

## Risco residual

Outros modelos, providers ou tarefas maiores ainda precisam de certificação
individual. O método deve manter o timeout e o estado `recovery_required`
mesmo que uma sessão anterior tenha sido bem-sucedida.

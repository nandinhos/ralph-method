# ADR-0013 — Retry do supervisor com novo fencing e heartbeat de verificação

## Contexto

Durante a execução supervisionada da `FEATURE-093-REGRESSION-RELEASE`, a
revisão read-only do OpenCode permaneceu ativa por mais tempo que o limite
`stale-after`. O controlador não emitia heartbeat durante a janela de
verificação e, ao detectar `process_missing`/`heartbeat_stale`, tentava
relançar o mesmo `lease_token` e o mesmo `attempt`.

Esse comportamento confundia uma execução longa com pane e, mais grave,
reutilizava uma autoridade de execução que já deveria estar fenced. O retry
acabava sem poder iniciar uma nova tentativa válida.

## Opções consideradas

1. Aumentar globalmente `stale-after` e aceitar a ausência de heartbeat.
2. Reutilizar o lease atual, registrando apenas `recovery.retry_started`.
3. Emitir heartbeat durante a revisão read-only e, após stale, registrar
   `recovery.required` antes de adquirir nova tentativa com novo lease e
   fencing token.

## Decisão

Adotamos a opção 3.

`runReadOnlyCommand()` aceita um callback opcional de heartbeat. A revisão
separada do OpenCode usa esse callback para registrar
`command.heartbeat` com `facts.phase=verification`, preservando a distinção
entre atividade do processo e atividade de saída.

O ramo stale do supervisor não reutiliza mais o lease. Ele:

1. encerra o grupo observado;
2. registra `recovery.required` de forma idempotente;
3. chama `beginFailedRetry()` com `preserve-tree=true`;
4. recebe novo `lease_token`, novo `attempt` e novo `fencing_token`;
5. inicia o bloco somente com essa nova autoridade.

O mesmo contrato é aplicado quando o processo termina sem evento terminal.

## Consequências

### Positivas

- revisões longas continuam visíveis ao monitor;
- uma execução stale não pode reusar lease ou tentativa anteriores;
- a árvore parcial é preservada para recuperação explícita e auditável;
- a sequência de tentativas fica verificável por `attempt` e hash de lease;
- o fluxo continua compatível com os cinco gates e com a autoridade única do
  `ralph-control`.

### Negativas

- cada retry gera novos eventos e uma nova tentativa formal;
- um heartbeat depende de o processo controlador continuar executando;
- o intervalo de stale ainda precisa ser configurado de acordo com o ambiente;
- recuperação após crash real continua exigindo evidência e não é convertida
  em avanço silencioso.

## Evidência

- `scripts/test-ralph-method.sh`: interrupção real do supervisor, novo
  `attempt` e leases distintos;
- `scripts/test-ralph-reconciliation.sh`: revisão read-only lenta com
  heartbeat de fase;
- `bash scripts/ci-portable.sh`: `163 asserts` verdes.

## Dono

Equipe do Ralph Method.

## Data

2026-08-11.

## Gatilho para revisitar

Revisitar se o supervisor passar a separar o monitor em processo independente
ou se gates e systematic debugging também forem executados em subprocessos
longos sem heartbeat próprio.

# Incidente 0013 — Retry stale reutilizava lease e ocultava revisão longa

## Sintoma

Na `FEATURE-093-REGRESSION-RELEASE`, a revisão técnica read-only do OpenCode
ficou ativa por mais de `stale-after=120s`. O monitor informou
`heartbeat_stale`, o supervisor tentou recuperações e terminou em
`recovery_required`, sem concluir a feature.

## Evidência

- Workflow: `wf_detector_bc_legacy_20260810_001`
- Feature: `FEATURE-093-REGRESSION-RELEASE`
- OpenCode: `1.18.16`
- Modelo: `opencode/deepseek-v4-flash-free`
- Implementação já produzida: commit `72831ee`
- Estado após a pane: `recovery_required`
- Processos associados ao run encerrados antes da nova retomada
- Eventos: `heartbeat_stale`, `recovery.retry_started` e
  `recovery.required`

## Causa raiz

Havia duas lacunas no controlador:

1. `runControlled()` entrava em `runSeparatedVerification()` sem emitir
   `command.heartbeat`; uma revisão longa parecia inativa mesmo com o
   processo vivo.
2. O ramo stale de `superviseWorkflow()` encerrava o processo, incrementava
   apenas o contador local e chamava `supervisorStartRun()` com o lease e o
   attempt antigos. Isso violava o fencing e produzia uma tentativa que não
   era uma nova tentativa de fato.

## Correção aplicada

- heartbeat periódico e sanitizado durante a revisão read-only, com
  `facts.phase=verification`;
- recuperação stale idempotente antes do retry;
- novo `attempt`, novo hash de lease e novo fencing token por retry;
- mesma correção para processo encerrado sem evento terminal;
- preservação explícita da árvore parcial para a nova tentativa.

## Validação

O teste de regressão foi executado primeiro contra o código anterior e falhou
porque o supervisor não concluiu após o retry stale. Depois da correção:

- `scripts/test-ralph-method.sh`: verde, com `feature.claimed` em attempts
  `[1, 2]` e dois leases distintos;
- `scripts/test-ralph-reconciliation.sh`: verde, com heartbeat da revisão
  lenta;
- `bash scripts/ci-portable.sh`: verde, `163 asserts`.

## Risco residual

O supervisor ainda deve ser retomado explicitamente se o próprio processo do
controlador morrer antes de registrar o próximo evento. A correção impede o
avanço indevido e a reutilização de lease, mas não transforma crash em sucesso.

## Estado

Corrigido na branch de evolução. A `FEATURE-093` deve ser retomada somente
após o commit desta correção e uma nova execução supervisionada com os cinco
gates.

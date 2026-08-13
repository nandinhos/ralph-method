# Incidente 0017 — Contexto seguro ausente no executor

## Sintoma

Na primeira validação do Ralph Method 0.8.0 instalado no `refactor-radar`, o
`bin/check` aprovou a primeira feature e interrompeu a segunda em
`recovery_required`. O bloco de teste usava `RALPH_FEATURE_KEY` para nomear o
artefato da feature; como o executor não recebia esse identificador, a segunda
tentativa não gerava o commit esperado.

## Causa raiz

O hardening que removeu `RALPH_WORKFLOW_ID` e `RALPH_FEATURE_KEY` confundiu
identificação operacional com capacidade de escrita. O hook precisa do
workflow e da feature para emitir feedback correlacionado, e runners legítimos
podem usar a chave para separar seus artefatos. O lease, as credenciais e os
proofs são as capacidades sensíveis e devem permanecer ausentes.

## Correção

O controlador passou a fornecer `RALPH_WORKFLOW_ID` e `RALPH_FEATURE_KEY` no
ambiente do processo controlado. O filtro continua removendo
`RALPH_LEASE_TOKEN`, `RALPH_OPENCODE_VERIFY_POLICY_PROOF` e
`RALPH_OPENCODE_VERIFY_AGENT`; `observe` permanece não mutante e os gates
continuam exclusivamente sob autoridade do controlador.

## Evidência

- `tests/Unit/RalphControlTest.php` — supervisor com duas features e cinco
  gates, incluindo a segunda execução após a primeira aprovação.
- `bash scripts/test-ralph-method.sh` — regressão do loop, guardrails e
  isolamento do executor.
- `bash scripts/ci-portable.sh` — suíte portátil completa após a correção.

## Risco residual

Os identificadores são visíveis ao processo executor e não devem ser tratados
como segredo. Eles não autorizam transição, lease, gate ou escrita no ledger.

## Prevenção

Separar explicitamente contexto de correlação de capabilities de mutação em
qualquer alteração futura no ambiente do executor; toda variável nova precisa
de classificação e teste de ausência/presença.

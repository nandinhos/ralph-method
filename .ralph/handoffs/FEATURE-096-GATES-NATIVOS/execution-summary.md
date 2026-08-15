# HND-2026-0007 — Resposta: gates nativos implementados (FEATURE-096)

- Documento: HND-2026-0007
- Origem: `ralph-method` (implementação nativa)
- Destino: `refactor-radar` (projeto-alvo)
- Estado: implementado e testado; aguardando ativação no projeto-alvo
- Política de conhecimento: non_blocking

## O que foi implementado (resposta ao HND-2026-0006)

1. **Contrato canônico de contexto por env** — `supervisorExecuteGateCommand`
   (`bin/ralph-control`) exporta `RALPH_WORKFLOW_ID`, `RALPH_FEATURE_KEY`,
   `RALPH_ATTEMPT`, `RALPH_GATE`, `RALPH_REPORT_PATH` e `RALPH_LEASE` ao
   comando de gate. O comando não recebe argumentos posicionais.
2. **Defaults nativos** — `supervisorGateCommand` passa a usar os wrappers
   instalados para os quatro gates executáveis: `ralph-run-quality.sh`,
   `ralph-run-runtime-evidence.sh`, `ralph-run-independent-gate.sh`
   (technical_review e curation). A configuração explícita
   (`RALPH_RUNTIME_EVIDENCE_CMD`, `RALPH_TECHNICAL_REVIEW_COMMAND`,
   `RALPH_CURATION_COMMAND`, `--<gate>-command`) tem prioridade.
3. **Wrappers unificados** — leem o contrato por env e, quando invocados pelo
   supervisor, apenas emitem evidência + exit code (o controlador registra o
   gate). Chamada manual com `--workflow/--feature/--lease` continua aceita.
4. **Defaults de evidência** — runtime_evidence:
   env → `scripts/*runtime-evidence*` → `bin/check`; technical_review: env;
   sem comando, rejeita sem inventar revisão; curation: env →
   `bin/ralph-knowledge --workflow --feature`.
5. **Documentação** — seção 6.1 do `AGENT_GUIDE` (contrato do comando de
   gate) e entrada no CHANGELOG 0.9.1.
6. **Regressão** — `scripts/test-ralph-gates-native.sh` (5 gates registrados
   no ledger, sem `gates_configuration_required`, contrato por env validado).

## Próximo passo no refactor-radar

Atualizar o método para a branch/versão que contém a FEATURE-096 (após o
merge) e re-rodar `ralph-control supervise` na feature que parou em
`gates_configuration_required` (runtime_evidence). A sessão da feature está
preservada em `awaiting_gates`; o supervisor deve retomar a partir do gate
pendente. Se o projeto quiser evidência de runtime real, definir
`RALPH_RUNTIME_EVIDENCE_CMD` ou criar `scripts/*runtime-evidence*`; o default
cai em `bin/check`.

## Evidência

- Implementação: `bin/ralph-control`, `scripts/ralph-run-*.sh`,
  `scripts/test-ralph-gates-native.sh`, `docs/AGENT_GUIDE.md`, `CHANGELOG.md`;
- origem do pedido: HND-2026-0006 (handoff do refactor-radar).

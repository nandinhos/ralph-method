# HND-2026-0008 — Recuperação de gate distinta entre defeito do comando e falha da feature

- Documento: HND-2026-0008
- Origem: `refactor-radar` (INC-2026-0007 — pane observada na fase 25)
- Destino: `ralph-method` (implementação nativa)
- Harness observado: OpenCode (o diagnóstico não depende do harness)
- Estado: proposta — aguardando implementação
- Política de conhecimento: non_blocking

## Contexto

Na ativação supervisionada do refactor-radar (fase 25, após FEATURE-096), o
gate `technical_review` foi rejeitado **duas vezes seguidas** por defeitos do
**comando de gate** (`scripts/ralph-review-feature.sh`), não da feature. Em
cada rejeição o fluxo entrou em `debugging_required`, exigiu systematic
debugging verificado e, na retomada, **re-executou o bloco completo**
(implementação opencode + `bin/check` + revisão) mesmo com a feature já
commitada e os gates `validation`, `quality` e `runtime_evidence` aprovados.
Foram três re-execuções de um bloco cujo código nunca mudou (~9–20 min cada),
travando o progresso por ~2h.

A raiz é de **método**, não de harness:

1. **O controlador não classifica o resultado do comando de gate.** Um
   `exit_code != 0` do comando vira `gate.rejected` → `debugging_required` da
   **feature**, sem distinguir "a evidência mostra falha da feature" de "o
   comando de gate quebrou". Nada sinaliza um `gate_harness_error` (comando
   sem evidência, saída vazia, contrato violado, crash).
2. **O retry pós-debugging re-executa o bloco inteiro.** O
   `recovery.retry_started` (retomada após `debugging.verified`) inicia nova
   tentativa do bloco, mesmo com a feature commitada e gates anteriores
   aprovados. Para um defeito do comando de gate, a correção só vale para o
   gate; re-implementar é desperdício.
3. **Sem self-test/preflight de comando de gate.** Não há como validar o
   contrato (env), a produção de evidência e o exit code de um comando de gate
   antes de uma sessão real.

## Objetivo

1. **Classificar o resultado do comando de gate** no `ralph-control`:
   `gate_rejected` (evidência mostra falha da feature) vs `gate_harness_error`
   (comando sem evidência, stdout vazio, crash, timeout ou contrato violado).
   O `debugging` de um `gate_harness_error` deve mirar o comando e não
   re-executar o bloco commitado.
2. **Retry de gate não re-executa bloco commitado**: se a feature está
   commitada e os gates anteriores passaram, a retomada re-rodada apenas o gate
   pendente/rejeitado — sem nova sessão de implementação.
3. **Exigir evidência não-vazia no contrato**: um comando de gate com `exit 0`
   e stdout vazio é `gate_harness_error` (ou o AGENT_GUIDE documenta que o
   stdout precisa conter a evidência mínima).
4. **Self-test de comando de gate**: `ralph-control gate --test` (ou similar)
   valida o comando configurado (env do contrato, evidência, exit code) contra
   um fixture, antes de gaterar trabalho real.

## Critérios de aceite (sugeridos)

- [ ] `ralph-control` distingue no ledger `gate.rejected` (feature) de
      `gate.harness_error` (comando), com evento e estado próprios.
- [ ] Um `gate_harness_error` leva o `debugging` a mirar o comando de gate e
      **não** re-executa o bloco já commitado; o retry roda só o gate.
- [ ] Comando de gate com `exit 0` e stdout vazio é classificado como defeito
      de harness (ou rejeitado com diagnóstico claro).
- [ ] `ralph-control gate --test <gate>` executa o comando configurado em modo
      fixture e reporta contrato/evidência/exit sem tocar no workflow.
- [ ] `AGENT_GUIDE` documenta a classificação e o self-test; CHANGELOG atualizado.

## Evidência

- `refactor-radar`, INC-2026-0007: `technical_review` rejeitado 2x (attempts 2
  e 3) por defeitos do comando; 3 re-execuções do bloco commitado (`3729c4e`);
  `debugging_required` → `debugging.verified` (`DBG-2026-0008/0009`) → retry.
- Ledger: `gate.rejected` + `debugging.required` para ambos os casos, sem
  distinção entre feature e comando.

## Regras obrigatórias do processo

- `ralph-control` permanece a única autoridade de estado, ledger e avanço;
- nenhum gate é aprovado por texto, screenshot ou promessa; a árvore deve
  permanecer intacta durante o comando de gate;
- não expor tokens, prompts completos, leases ou proofs;
- a mudança não pode quebrar a configuração explícita por env já existente nem
  o comportamento de `gate_rejected` legítimo.

## Checklist de encerramento do agente de destino

- [ ] li o `AGENT_GUIDE` e o INC-2026-0007 de origem;
- [ ] classifiquei `gate_rejected` vs `gate_harness_error` no ledger/estados;
- [ ] retry de gate não re-executa bloco commitado;
- [ ] stdout vazio de comando de gate é tratado como defeito de harness;
- [ ] implementei `gate --test` (fixture) e documentei no `AGENT_GUIDE`;
- [ ] validei com `ralph-control supervise` num projeto com comando de gate
      customizado defeituoso (diagnóstico rápido, sem re-execução do bloco);
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.

# HND-2026-0015 — Resposta ao incidente 0018 (bloco deixa árvore suja e o retry trava)

- Documento: HND-2026-0015
- Origem: `ralph-method` (correção nativa do método)
- Destino: `refactor-radar` (projeto de campo, workflow `wf_ralph_20260805_001`)
- Estado: **corrigido na branch `feat/trace-cockpit`** (commit `a899e9f`, CI portátil verde); aguardando verificação em campo
- Política de conhecimento: non_blocking

## O que foi entregue (resposta ao incidente 0018)

O incidente 0018 (fases 26, 29, 31 e 33 do `refactor-radar`) foi corrigido no
método em **três camadas**, cobertas pelo novo teste
`scripts/test-ralph-dirty-reconcile.sh` incluído na CI portátil:

1. **Camada A — reconciliação de árvore suja sob sinal do controlador.**
   `ralph-control run` exporta `RALPH_RECONCILE_DIRTY=1` para o bloco quando a
   feature está em retry com `claim.recovery=true`. Com o sinal, o preflight do
   `ralph.sh` audita a árvore (`git status --short`) e **continua** sobre o
   trabalho parcial do bloco interrompido — o retry não aborta mais em
   `Árvore de trabalho suja`. O abort fail-closed permanece para uso
   direto/interativo sem o sinal.
2. **Camada B — diagnóstico fiel com `cause_kind`.** O relatório de debug
   (`debug` / `RALPH_DEBUG_COMMAND`) exige `cause_kind` no enum
   `harness_defect | feature_bug | capacity | unknown`; relatório sem causa é
   rejeitado (`debugging.rejected`), eliminando o "auto-debug genérico" que
   verificava sem descrever o estado real. A causa é persistida no
   `debugging.verified`. Pós-debugging:
   - bloco **não commitado** → re-executa o bloco (continua o trabalho parcial);
   - bloco **commitado** + `harness_defect`/`capacity` + falha de gate →
     `beginGateRetry` (não re-executa o bloco);
   - bloco **commitado** + `feature_bug` → `recovery_required` com reason
     `feature_bug_committed` (correção de código não é resumida
     silenciosamente a retry de gates).
3. **Camada C — evidência de `feature_bug` validada.** `cause_kind=feature_bug`
   exige `evidence_refs` apontando para arquivos que existam no repositório;
   evidência inexistente é rejeitada.

## Regressão

- `check-shell.sh`, `check-doc-sync.sh` — exit 0;
- `ci-portable.sh` (25 testes, inclui o novo `test-ralph-dirty-reconcile.sh`)
  — exit 0, CI remota em `feat/trace-cockpit` verde;
- `test-ralph-gate-recovery.sh` — verde com fixture atualizado
  (`cause_kind=harness_defect`), cenário "erro de harness não re-executa o
  bloco" preservado.

## Verificação pedida no campo (`refactor-radar`)

1. Reproduzir o cenário do incidente: com o método atualizado
   (branch `feat/trace-cockpit`, commit `a899e9f`), retomar o `supervise` com
   árvore suja deixada por bloco interrompido e confirmar que o retry **não
   aborta** no preflight e continua sobre o trabalho parcial;
2. confirmar que o `RALPH_DEBUG_COMMAND` do projeto agora emite `cause_kind`
   (o `ralph-diagnose.php` do cockpit já usa `harness_defect`); relatório sem
   causa deve ser rejeitado com `debugging.rejected`;
3. se o diagnóstico indicar `feature_bug`, confirmar `evidence_refs` existentes
   e que o workflow vai a `recovery_required` (não a um retry de gates que não
   corrige o código);
4. fechar o incidente 0018 no projeto após a verificação em campo.

## Bloqueios

Nenhum. A correção está commitada e com CI verde; a promoção formal
(v0.10.1) será feita após a verificação em campo e o fechamento do incidente.
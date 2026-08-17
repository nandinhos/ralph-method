# Incidente 0018 — Bloco deixa árvore suja e o retry trava em loop de preflight

**Data:** 2026-08-16
**Corrigido em:** 2026-08-17 (método v0.10.1 em desenvolvimento)
**Componente:** executor controlado (`ralph-control run` / `ralph.sh`) no fluxo supervisionado
**Projeto de campo:** `refactor-radar` (workflow `wf_ralph_20260805_001`)
**Severidade:** alta — bloqueia o workflow; exige intervenção manual a cada ocorrência
**Status:** corrigido — aguardando verificação em campo pelo `refactor-radar`

## Contexto

No fluxo supervisionado (`ralph-control supervise --engine opencode`), o bloco
(`ralph.sh --no-verify`) implementa a fase e deve commitar a cada fase aprovada.
Na prática, em várias fases o bloco **escreve a implementação mas não a
commita** — por interrupção do processo (exit 143 / SIGTERM) ou por um gate
interno reprovar e o bloco ser encerrado antes de commitar. A árvore fica suja.

## Sintoma

Sequência observada repetidamente no `refactor-radar` (fases 26, 29, 31 e 33):

1. O bloco escreve a implementação (dezenas de arquivos) na árvore, mas não
   commita.
2. No retry, o preflight do `ralph.sh` aborta **imediatamente**:
   `Árvore de trabalho suja. ralph commita por fase e engoliria suas mudanças.`
   → `block.finished exit=1` em menos de 2 segundos.
3. O controlador registra `debugging.required`; o auto-debug
   (`RALPH_DEBUG_COMMAND`) emite `debugging.verified` com um relatório
   **genérico** que não corresponde ao estado real.
4. O retry re-aborta na mesma árvore suja → após 3 retries, `recovery_required`
   e o supervisor **encerra**, deixando o workflow travado.

Em uma das fases (29), a implementação deixada estava verde (`bin/check` ok) e
foi resgatada por commit manual. Em outras (26, 33), estava incompleta/vermelha
e precisou ser descartada e re-implementada. Em todos os casos, a intervenção
manual (limpar/reset/commit + `recover`) foi obrigatória.

## Análise da causa raiz

1. **O bloco não commita o trabalho parcial.** Quando um gate interno reprova
   ou o processo é interrompido, a implementação fica na árvore sem commit.
2. **O preflight aborta em árvore suja e impede qualquer progresso.** O
   `ralph.sh` recusa rodar com árvore suja ("engoliria suas mudanças"), então o
   retry não consegue nem continuar o trabalho nem re-implementar — o trabalho
   que ficou sujo é exatamente o que precisava ser commitado ou corrigido.
3. **O `debugging.verified` automático não resolve a árvore suja.** O auto-debug
   emite verificação com relatório genérico, mas a árvore continua suja; o retry
   re-aborta no mesmo ponto. O diagnóstico não é fiel ao estado.
4. **Não há caminho suportado para os dois casos que travam:**
   - continuar/reconciliar a partir de uma árvore suja deixada por bloco
     interrompido (preservar o trabalho válido);
   - re-implementar uma feature cujo código commitado tem **bug real**
     encontrado pela revisão independente (o retry pós-debugging resume apenas
     os gates para feature commitada, sem re-executar o bloco).

## Correção e mitigação

Correção aplicada no método em 2026-08-17, em três camadas (cobertas pelo
`scripts/test-ralph-dirty-reconcile.sh`):

1. **Camada A — reconciliação de árvore suja sob sinal do controlador.** O
   `ralph-control run` exporta `RALPH_RECONCILE_DIRTY=1` no ambiente do bloco
   quando a feature está em retry com `claim.recovery=true`. O preflight do
   `ralph.sh`, com o sinal, audita e **continua** sobre o trabalho parcial
   (listando `git status --short`); sem o sinal, o abort fail-closed
   "Arvore de trabalho suja" permanece para uso direto/interativo. O trabalho
   parcial do bloco interrompido não trava mais o retry.
2. **Camada B — diagnóstico fiel com `cause_kind`.** O relatório de debug
   (`debug` / `RALPH_DEBUG_COMMAND`) agora exige `cause_kind` no enum
   `harness_defect | feature_bug | capacity | unknown`; relatório sem causa é
   rejeitado (`debugging.rejected`), impedindo o "auto-debug genérico" que
   verificava sem descrever o estado real. A causa é persistida no
   `debugging.verified`. Pós-debugging:
   - bloco **não commitado** → re-executa o bloco (continua o trabalho);
   - bloco **commitado** + `harness_defect`/`capacity` + falha de gate →
     `beginGateRetry`;
   - bloco **commitado** + `feature_bug` → `recovery_required` com reason
     `feature_bug_committed` (correção de código exigida não resumida
     silenciosamente a gates).
3. **Camada C — evidência de `feature_bug` validada.** Quando `cause_kind =
   feature_bug`, o relatório deve referenciar em `evidence_refs` arquivos que
   existam no repositório; evidência inexistente é rejeitada
   (`debugging.rejected`).

Mitigação operacional imediata (adotada no projeto de campo): quando o bloco
deixa árvore suja, o operador valida o trabalho (`bin/check`), commita se verde
ou limpa se vermelho, reseta a feature (`recover`) e retoma o `supervise`.

## Referências

- Evidências no `refactor-radar`: `block.finished` com exit 1 por
  "Árvore de trabalho suja" nas fases 26, 29, 31 e 33; `recovery_required`
  após retries; intervenções manuais registradas na condução do workflow
  `wf_ralph_20260805_001`.

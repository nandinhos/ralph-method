# Incidente 0012 — Aprovação de feature já implementada bloqueada

## Sintoma

Na execução real de `FEATURE-092-EVOLVE-BC-LEGACY` pelo OpenCode, a sessão de
implementação terminou com exit code `0`, a revisão independente terminou com
exit code `0` e os cinco gates foram aprovados. A supervisão, porém, terminou
com:

```text
commit da feature não tem o base_commit da tentativa como pai imediato
```

## Evidência

- Workflow: `wf_detector_bc_legacy_20260810_001`
- Tentativa: `7`
- Runner: OpenCode `1.18.16`
- Modelo: `opencode/deepseek-v4-flash-free`
- `base_commit`: `c318013937362c23c8b1a90e985e62e791d42d5a`
- `result_commit`: o mesmo `HEAD`
- `base_tree_hash` e `result_tree_hash`: o mesmo fingerprint
- Implementação: `phase_already_done`, nenhum commit criado
- Gates: `validation`, `quality`, `runtime_evidence`, `technical_review` e
  `curation` passaram

## Causa raiz

`scripts/ralph.sh` já possuía o contrato correto de idempotência: quando a
feature estava presente no `HEAD`, validava a suíte, mantinha a árvore limpa e
terminava sem criar commit vazio. `approveFeature()` em `bin/ralph-control`,
entretanto, tratava a regra de commit-filho como universal e não tinha uma
representação auditável para o caso no-op.

## Correção

O controlador passou a separar dois caminhos:

- `new_commit`: mantém a exigência de um commit-filho imediato;
- `already_present`: exige que base, árvore, commit e resultado sejam o
  checkout atual, registra `no_op=true` e não cria commit artificial.

Também foi corrigida a falha de recuperação: resultado stale antes da
aprovação agora gera `recovery.required` com os hashes observados, em vez de
deixar a feature indefinidamente em `awaiting_gates`.

## Prevenção

`scripts/test-ralph-noop-approval.sh` comprova aprovação, auditoria, handoff,
liberação e avanço de uma feature sem commit vazio. A execução portátil também
mantém essa regressão na lista oficial da CI.

## Estado

Corrigido na branch de evolução; a tentativa real que encontrou o defeito deve
ser retomada por recovery explícito após a promoção do ajuste do controlador.

# Ralph Method 2.0 — Onda 2 (Hardening de Segurança e Adapter Gates)

<!-- inputs:
  - Métricas de tempo da Onda 1 (`bin/ralph-time-report.php`): total 15h08m,
    59% em esperas, 26 commits de fix durante a execução
  - Relatório de panes Onda 1 (105 eventos de pane no ledger)
  - Memórias validadas no hub: `01a024a8` (gargalo de espera), `01a02532` (OOM)
  - Backlog `BL-0005` (métricas por feature — entregue a base; item fechado)
  - Plano do projeto: `.spec/init/project-phases.md`
-->

## Overview

A **Onda 1 — Telemetria Contínua** (FEATURES-101A..101F) provou que o método
funciona quando é observado e recuperado. As métricas (`bin/ralph-time-report.php`)
confirmaram que o gargalo dominante foi **espera** (rate limits, paradas do
supervisor, retries silenciosos) — 8h53m de 15h08m (59%). Os 26 commits de
fix durante a Onda 1 tocam exatamente o que ficou descoberto: OOM silencioso
do controlador, claim órfão em claim/retry, reconfirmação de exit code, prompt
verify read-only, e o elo final do ciclo de recovery (árvore suja →
`recovery.required` em vez de morte do supervisor). A fundação de **observação**
está em pé. Falta endurecer a fundação de **execução**: o controlador ainda
pode parar por sinal de segredo, ainda confunde "policy violated" com "feature
bug", ainda aceita Adapter com `permission_policy_status=declared` sem ter
sobrevivido a adversarial real, e ainda aceita `event_type` desconhecido ad-hoc.

A **Onda 2 — Hardening de Segurança e Adapter Gates** fecha essas fendas uma
feature por bloco (5 gates cada), com critério mensurável e ligação direta às
lições aprendidas na Onda 1.

## Key Concepts

- **Redação, não rejeição:** `sanitize()` ao detectar padrão sensível deve
  redigir (`[REDACTED:tipo]`) e prosseguir, registrando `facts.redacted=true`,
  em vez de abortar o bloco inteiro com `fail()` (que já matou o método em
  pane similar da Onda 1 com o fixture canário).
- **Política como classificação de causa raiz:** `policy_violation` deve
  virar `status: failed` com `recovery_required/cause_kind: harness_defect` —
  não `interrupted` (que mistura falha de harness com feature_bug e gera
  decisões erradas — 25 panes da Onda 1 foram classificadas com causa
  ambígua dessa forma).
- **Promoção por evidência, não por opt-in:** Adapters entram na cadeia
  executável só depois do **adversarial real** + **hero flow** em campo. O
  Cursor opt-in declarado da 101A existe, mas se provou em produção? Não
  fechamos esse caminho na Onda 1 — corrigir antes de virar base de outras
  ondas.
- **Validação centralizada do contrato:** `appendEvent` rejeita `type`
  desconhecido de forma explícita (`event.rejected`) e auditável, sem abrir
  o hash chain.

## Key Decisions & Trade-offs

- **Redação vs rejeição.** A versão anterior prefere `fail()` (fail-closed).
  Essa onda vira o pêndulo para `sanitize()` redactar e prosseguir, com
  `redacted=true` no `facts`. Trade-off: o método nunca fica preso num
  segredo detectado, mas o ledger pode crescer com `event.rejected` em casos
  que o redaction marcou como redacted mas não foi sanitizado no sink
  consumidor — esse risco é coberto pela telemetria (`command.heartbeat`
  leva o `redacted_count`).
- **`policy_violation` ≠ `feature_bug`.** O branch atual (`debug.rejected` →
  `recovery_required`) trata policy violation como bug de feature. Aqui
  separamos: o `debug` valida causa por `cause_kind` documentado; policy
  violation só é `feature_bug` se houver evidência em código (`evidence_refs`).
  Caso contrário, `harness_defect` e o supervisor rebaixa + registra
  knowledge candidate para o operador decidir próxima política.
- **Cursor rebaixado, não banido.** Cursor já demonstrou opt-in + execução
  em campo (FEATURE-100A) mas sem adversarial+hero completos. Decidimos
  manter o opt-in, mas **bloquear o uso em produção** enquanto não houver
  prova reprodutível. Decisão registrada em ADR novo (rascunho em
  `docs/adr/ADR-0033-cursor-promotion.md` a ser criado com a feature).

## Metrics

A Onda 2 usa o instrumento herdado da Onda 1 (`bin/ralph-time-report.php`)
como barreira de aceite em vez de reescrever telemetria. Os critérios:

- **Zero `policy_violation` classificada como `feature_bug`** durante a onda
  inteira (métrica: `grep cause_kind feature_bug events.jsonl | grep
  policy_violation` retorna vazio).
- **Zero `fail()` por `secret_detected`** durante a onda inteira (métrica:
  `grep 'secret_detected' reports/` retorna vazio em qualquer RPT/DBG).
- **Cursor: 0/0 promoção** até `test-cursor-adversarial` e `test-cursor-hero`
  passarem — gated por `--promote` flag no provider-status.
- **Tempo médio por feature ≤ 30min**, mantendo o ritmo da Onda 1 de
  21m (101C/101D com 1 attempt). Se a 102 atrasar mais que 1h, isso vira
  sinal de drift de hardening vs. feature_bug — debugging obrigatório.

## Cross-Feature Dependencies

A Onda 2 depende exclusivamente da Onda 1 (telemetria + watchdog + cursor
otimizado). Onda 3 (adapters unificados), 4 (desempenho) e 5 (testes/CI) ficam
  para ondas futuras e podem lançar features adicionais em paralelo via
  branches isolados depois que esta onda completar.

## References

- `.spec/init/project-phases.md` — fases globais do projeto
- `docs/backlog.md` — backlog consolidado
- `docs/reports/relatorio-tempo-onda1.md` — métrica herdada
- `docs/handoffs/HO-2026-08-21-onde2-planejamento.md` — handoff para a
  nova sessão
- memórias do hub: `01a024a8`, `01a02532`

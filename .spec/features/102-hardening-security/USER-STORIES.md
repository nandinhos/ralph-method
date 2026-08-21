# Ralph Method 2.0 — User Stories (Onda 2: hardening de segurança)

<!-- inputs: project-description.md@sha256:<gerado-no-ciclo> -->

## Overview

A Onda 2 endurece o `ralph-control` contra entradas adversariais (segredos
detectados, políticas violadas, tipos de evento desconhecidos) e padroniza a
fronteira de promoção do Adapter Cursor. As métricas e panes da Onda 1
(105 eventos de pane, 26 commits de fix) ancoram quatro features, cada uma
com os 5 gates.

**User Types:** os mesmos da Onda 1 (operador, agente executor, consumidor).

---

## 1. Sanitize redige em vez de rejeitar

### US-2.1: `sanitize()` redacta segredos detectados
**As a** agente executor / operador
**I want to** que `sanitize()` substitua padrões sensíveis por marcadores
redigidos e prossiga — em vez de `fail()` que mata o bloco
**So that** o método nunca fique preso por um canário, uma chave ou um
token detectado pelo sanitizador.

**Acceptance Criteria:**
- [ ] `sanitize()` retorna string redigida com `[REDACTED:tipo]` (ex.: `[REDACTED:token]`) quando encontra padrão de segredo
- [ ] Função registra `facts.redacted = true` no evento gerado e mantém o ledger íntegro
- [ ] Não há `fail()` chamado por `secret_detected` durante a Onda 2 inteira (métrica herdada)
- [ ] Fixture canário: input com `token=abc123` retorna `[REDACTED:token] abc123` para `abc123 [REDACTED:token]`
- [ ] Teste: hook preflight detecta `redacted_count` no próximo heartbeat

### US-2.2: Redacción preserva debuggability sem vazar
**As a** operador
**I want to** que o evento redigido permaneça rastreável no ledger (id do evento,
feature, causa) — sem o valor redigido em si
**So that** um incidente de segurança seja forense, sem abrir a porta de saída.

**Acceptance Criteria:**
- [ ] `event.redacted` contém apenas o marcador `[REDACTED:tipo]` + contexto (path, feature_key, attempt)
- [ ] `facts.redacted_count = N` (quantos trechos foram redigidos, não o quê)
- [ ] Relatório de debugging (`DBG-YYYY-NNNN`) inclui apenas path do arquivo, não o trecho redigido

---

## 2. Cursor só promover com prova em campo

### US-2.3: Cursor rebaixado até provar adversarial+hero
**As a** operador
**I want to** que o Adapter Cursor rode apenas quando `adversarial` e
`hero` passarem em campo, mesmo que o opt-in declarado já exista
**So that** a promoção de Cursor use o mesmo rito de prova do agy
(FEATURE-095 / ADR-0017) e não fique como promessa de opt-in.

**Acceptance Criteria:**
- [ ] Provider-status mostra caminho de promoção: `optin`, `adversarial`, `hero`, `promoted` (todos os 4 campos explícitos)
- [ ] Cursor só roda em produção quando `promoted=true` (sinal verde nos 4 campos) — caso contrário, supervisor rebaixa para opencode
- [ ] `test-cursor-adversarial.sh` (≥3 cenários hostis executados) — sem isso, `promoted.adversarial = false`
- [ ] `test-cursor-hero.sh` (cenário end-to-end em checkout de campo) — sem isso, `promoted.hero = false`
- [ ] ADR novo: `docs/adr/ADR-0033-cursor-promotion.md` (decisão + critérios)
- [ ] Em `adversarial=false` OU `hero=false`, comandos `--engine cursor` retornam `fail('cursor rebaixado; rode tests/cursor-adversarial.sh e test-cursor-hero.sh')`

---

## 3. policy_violation → `status: failed` (não interrupted/feature_bug)

### US-2.4: Violação de policy classifica como harness_defect
**As a** agente executor
**I want to** que `policy_violation` (provider circuit aberto, divergence de
execution_policy_hash, permissões violadas) seja classificada como
`cause_kind: harness_defect` e levante `recovery_required`
**So that** o método saiba claramente que deve rebaixar/reconciliar — não
tratar como bug de feature e pedir re-implementação.

**Acceptance Criteria:**
- [ ] Quando o controller detecta policy divergente em runtime, o bloco vira `status: failed`, `gate.rejected`, `reason: policy_violation`
- [ ] `recovery.required` é registrado com `cause_kind: harness_defect` e `reason: policy_violation`
- [ ] `debug` exige `evidence_refs` em código para classificar `feature_bug` — sem `evidence_refs`, classifica `harness_defect`
- [ ] Métrica da Onda 2: `grep cause_kind feature_bug events.jsonl | grep -c policy_violation` retorna `0` ao final da onda
- [ ] `approveFeature` rejeita resultado com `status: failed/feature_bug` quando a causa for policy (devolve a re-decisão ao operador via `recovery_required`)

### US-2.5: Recovery não reinicia tentativa se policy ainda divergente
**As a** operador
**I want to** que o supervisor **não** tente `retry` automaticamente quando a
causa é `harness_defect/policy_violation` e a policy ainda estiver divergente
**So that** o método não entre em loop de recovery que eu autorizei a resolver.

**Acceptance Criteria:**
- [ ] Antes do `beginFailedRetry`, supervisor re-valida o `execution_policy_hash` congelado
- [ ] Se divergente, supervisor emite `recovery.required` com `reason: policy_not_reconciled` e não inicia tentativa
- [ ] Lock do tipo `policy.lock` impede nova claim até `reconcile` ou re-init

---

## 4. Validação centralizada do contrato de eventos

### US-2.6: `appendEvent` rejeita tipo desconhecido de forma auditável
**As a** agente executor
**I want to** que `appendEvent` valide `type` contra uma enumeração canônica
e registre `event.rejected` em vez de propagar evento com tipo fora do contrato
**So that** panes Onda 1 (commit `7ef4773`) fiquem eliminadas — a validação
está centralizada, não espalhada em call-sites.

**Acceptance Criteria:**
- [ ] Enumeração `RALPH_KNOWN_EVENT_TYPES` em `bin/ralph-control` lista todos os tipos válidos (incluindo `knowledge.telemetry`, `telemetry.activity`, `gate.stalled`, `recovery.required` etc.)
- [ ] `appendEventUnlocked` (e wrapper `appendEvent`) checa `type in RALPH_KNOWN_EVENT_TYPES` antes de montar o evento
- [ ] Tipo desconhecido registra `event.rejected` com `idempotency_key` único e **não propaga** o evento inválido (fail-closed sem derrubar o supervisor)
- [ ] Teste de fuzz: 100 tipos aleatórios inválidos geram 100 `event.rejected` e nenhum evento com tipo inválido

---

## Cobertura por feature × gate (matriz de aceite)

| US | feature_key | validation | quality | runtime_evidence | technical_review | curation |
|---|---|---|---|---|---|---|
| US-2.1, US-2.2 | `FEATURE-102A-SANITIZE-REDACT` | ações com `REDACTED:tipo` quebram o fluxo? | suite verde | fixture canário | sem run_command | knowledge |
| US-2.3 | `FEATURE-102B-CURSOR-REBAIXADO` | provider-status campos | suite verde | adversarial + hero | sem run_command | knowledge (ADR-0033) |
| US-2.4, US-2.5 | `FEATURE-102C-POLICY-FAILED` | divergence → recovery_required | suite verde | policy divergente | sem run_command | knowledge (error/lesson) |
| US-2.6 | `FEATURE-102D-EVENT-VALIDATION` | enum canônica + event.rejected | suite verde | fuzz 100 | sem run_command | knowledge (best_practice) |

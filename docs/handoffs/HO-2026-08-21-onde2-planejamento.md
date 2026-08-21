# Handoff — HO-2026-08-21-001 · Onda 2 (planejamento)

> Handoff documental de **transição de sessão**: a sessão atual termina com a
> Onda 1 completa e o plano da Onda 2 já no repositório. A próxima sessão abre
> este arquivo e continua do ponto exato. Não requer execução do `ralph-control`;
> é estado consolidado + próximo passo concreto.

---

## 1. Posição final da sessão atual

**Repositório:** `/home/nandodev/projects/ralph-method` (branch `feat/ralph-method-2.0`)
**Clone de execução:** `/tmp/ralph-method-2.0-field` (mesma branch; usado para a Onda 1)

### 1.1 Onda 1 — telemetria contínua (COMPLETA, 6/6 features liberadas)

```bash
php bin/ralph-time-report.php \
  --ledger /tmp/ralph-method-2.0-field/.git/ralph-control/events.jsonl \
  --workflow wf_ralph_method_2_0_onda1 --format md
```

Resumo tabular:

| Feature | Tempo | Implementação | Esperas | Attempts | Gates |
|---|---|---|---|---|---|
| 101A — Contrato de telemetria | 11h25m | 4h59m (43%) | 6h24m (56%) | 53 | 14✅ 4❌ |
| 101B — Watchdog de gates | 44m | 7m51s (18%) | 34m (78%) | 2 | 5✅ 0❌ |
| 101C — Terminal dashboard | 21m49s | **20m04s (92%)** | 1s | 1 | 5✅ 0❌ |
| 101D — Systematic debugging | 20m55s | **19m30s (93%)** | 1s | 1 | 5✅ 0❌ |
| 101E — Conhecimento em tempo real | 1h34m | 8m16s (9%) | 1h24m (89%) ⚠ | 2 | 5✅ 0❌ |
| 101F — Cockpit stream | 41m49s | 9m31s (23%) | 29m (69%) | 2 | 5✅ 0❌ |
| **Total** | **15h08m** | **6h04m (40%)** | **8h53m (59%)** | 61 | **39✅ 4❌** |

⚠ 101E teve pane OOM no supervisor (crash silencioso por `readEvents()`
com `file()` no ledger de 18MB/6754 eventos, limite 128MB) → fix `8b2e837`
(memory_limit 512M + streaming) + `e993c6d` (ciclo recovery alinhado: árvore
suja → `recovery.required` em vez de morte do supervisor).

### 1.2 Fixo entregue na sessão

| Commit | Descrição |
|---|---|
| `55b489e` | `bin/ralph-time-report.php` + relatório real (BL-0005, métricas de tempo por feature) |
| `e9b443f` | `scripts/ralph-live-tail.sh` (live-tail com fusion de ledger + monitor + supervisor log) |
| `8b2e837` | Fix OOM (memory_limit + readEvents streaming) + `scripts/ralph-anomaly-observer.sh` |
| `e993c6d` | Ciclo recovery alinhado (árvore suja → `recovery.required` em vez de morte) |
| `de0a9f0` | Live-tail termina ao detectar `complete` (aviso claro + exit 0) |
| `284ad6e`, `35c5e64` | Fix do technical_review com agy (perfil do engine no gate + prompt verify read-only) |
| **Merges** | `953e18e`, `665d110` (fases 1-4 + 5-6 do método trazidas do clone) |

### 1.3 Posição do clone de execução

- Branch `feat/ralph-method-2.0` à frente do principal em 5+ commits (handoffs
  `b004b35`, `6e0c0e4`, `c0c639a`, `518574e`, `d09c7c9`, `13b8cf2` e
  handoffs `e50fdd0`, `54e09b5`, `fc1ba19`, `dd9d12e`, `2b896fa`, `00ae86f`).
- Working tree: limpo (Onda 1 encerrou; supervisor morreu; `git status` clean).
- **Ação da próxima sessão:** opcionalmente `git fetch` + `merge --ff-only`
  para alinhar (principal já está com fast-forward atual até `665d110`).
  Commits futuros da Onda 2 devem entrar via o mesmo fluxo.

### 1.4 Processos rodando

**Nenhum** (foram parados manualmente após a Onda 1):

- `ralph-control supervise` — morto (workflow completo).
- `ralph-live-tail` (`PID 3410839`) — **morto nesta sessão** (era o processo
  antigo pré-fix; o novo detecta `complete`).
- `ralph-anomaly-observer` (`PID 34367`) — morto.
- Watcher de marco (`PID 3250547`) — morto.

---

## 2. Onda 2 — hardening de segurança (PLANO PRONTO, AGUARDANDO INIT)

### 2.1 Documentos criados nesta sessão

Todos versionados em `/home/nandodev/projects/ralph-method/.spec/features/102-hardening-security/`:

| Arquivo | Função |
|---|---|
| `PROJECT-DESCRIPTION.md` | Contexto, key concepts, decisões, métricas herdadas, dependências |
| `USER-STORIES.md` | 6 US cobrindo 4 features, critérios Gherkin, matriz US × gate |
| `DATABASE-SCHEMA.md` | Fixtures canônicos (redaction canário, cursor promotion state, policy divergence, known event types) |
| `PHASES.md` | 4 phases (1 por feature), invariantes herdadas da Onda 1 |
| `workflow.json` | Fila executável para `ralph-init plan/apply`: 4 features, `wf_ralph_method_2_0_onda2_hardening` |

### 2.2 As 4 features da Onda 2 (em ordem de execução)

1. **FEATURE-102A-SANITIZE-REDACT** — `sanitize()` redacta segredos em vez
   de rejeitar. **Baseado na pane 101A do canário quase-vazar.**
2. **FEATURE-102B-CURSOR-REBAIXADO** — Cursor só promover com
   `adversarial + hero` em campo. **Fecha a dívida da FEATURE-100A.**
3. **FEATURE-102C-POLICY-FAILED** — `policy_violation` → `status: failed`
   (`cause_kind: harness_defect`), nunca `feature_bug`. **Baseado nas
   ambiguidades de classificação da Onda 1.**
4. **FEATURE-102D-EVENT-VALIDATION** — `appendEvent` valida tipo via enum
   canônica; tipo desconhecido vira `event.rejected`. **Centraliza o que
   101A fez ad-hoc em cada call-site.**

### 2.3 Métricas da Onda 2 (já definidas no plano)

- `grep '"cause_kind": *"feature_bug".*policy_violation' events.jsonl`
  deve retornar **`0`** ao final da onda.
- `grep '"reason": *"secret_detected"' reports/*.log` deve retornar **`0`**
  durante toda a onda.
- Cursor: `promoted=false` até `tests/test-cursor-adversarial.sh` +
  `tests/test-cursor-hero.sh` passarem.
- Tempo médio por feature ≤ 30min (ritmo da Onda 1 em 101C/101D: ~21min/1
  attempt).

### 2.4 Passo a passo para iniciar a execução (PRÓXIMA SESSÃO)

```bash
# 1. Confirmar clone de execução limpo
cd /tmp/ralph-method-2.0-field
git status --short        # esperado: clean
git fetch /home/nandodev/projects/ralph-method feat/ralph-method-2.0
git merge --ff-only FETCH_HEAD   # alinhar com o plano da Onda 2

# 2. Provisionar o workflow no clone (ler o plano, criar .ralph-init/)
bash /home/nandodev/projects/ralph-method/bin/ralph-init plan \
  --project /tmp/ralph-method-2.0-field
bash /home/nandodev/projects/ralph-method/bin/ralph-init apply \
  --project /tmp/ralph-method-2.0-field

# 3. Relançar o supervisor para a Onda 2
cd /tmp/ralph-method-2.0-field
nohup bash /home/nandodev/projects/ralph-method/scripts/ralph-supervise-onda1.sh \
  > /tmp/ralph-supervise-onda2.log 2>&1 &  # ajustar para o env da Onda 2

# 4. Acompanhar ao vivo (auto-encerra quando a onda completa)
nohup bash /home/nandodev/projects/ralph-method/scripts/ralph-live-tail.sh \
  --tick 10 > /tmp/ralph-live-tail.out 2>&1 &

# 5. Observer de anomalias (segundo plano)
nohup bash /home/nandodev/projects/ralph-method/scripts/ralph-anomaly-observer.sh \
  --tick 30 > /tmp/ralph-anomaly-observer.out 2>&1 &

# 6. Relatório de tempo sob demanda (gate quality e fim de cada feature)
php /home/nandodev/projects/ralph-method/bin/ralph-time-report.php \
  --ledger /tmp/ralph-method-2.0-field/.git/ralph-control/events.jsonl \
  --workflow wf_ralph_method_2_0_onda2_hardening --format md
```

> Observação: ajustar `test_command` no `workflow.json` se quiser usar a suite
> leve (já está como `bash scripts/check-shell.sh && bash scripts/test-ralph-method.sh`
> neste plano; `ci-portable.sh` fica como validação de release).

---

## 3. Lições aprendidas (consolidado das memórias do hub + plano)

| Lição | Origem | Onde aplicar |
|---|---|---|
| `readEvents()` em streaming + memory_limit | OOM silencioso (128M) | Onda 1 — já fixado |
| Árvore suja → `recovery.required` em vez de morte | Loop infinito do supervisor | Onda 1 — já fixado |
| Engine com adapter comprovado (agy) > modelos gratuitos | 56% do tempo em espera (rate limit) | Onda 1 — já aplicado |
| `sanitize()` redacta em vez de rejeitar | Pane 101A com canário | **Onda 2 — 102A** |
| `policy_violation` ≠ `feature_bug` | Classificação ambígua (25 panes) | **Onda 2 — 102C** |
| Cursor precisa de adversarial+hero | Opt-in da FEATURE-100A sem prova | **Onda 2 — 102B** |
| `appendEvent` valida type centralizadamente | Commit `7ef4773` ad-hoc | **Onda 2 — 102D** |
| Live-tail encerrar em `complete` | Loop infinito pós-conclusão | Onda 1 — já fixado |
| Observer captura OOM/crash silencioso | Pane 101E | Onda 1 — já entregue |

**Memórias válidas no hub:** `01a024a8` (gargalo de espera), `01a02532`
(OOM + fix streaming).

---

## 4. Estado das ferramentas e comandos úteis

```bash
# Status do workflow
php bin/ralph-control status --workflow wf_ralph_method_2_0_onda2_hardening

# Monitor (snapshot JSON read-only)
php bin/ralph-monitor --root /tmp/ralph-method-2.0-field \
  --controller bin/ralph-control \
  --workflow wf_ralph_method_2_0_onda2_hardening --once --json

# Relatório de tempo da onda atual
php bin/ralph-time-report.php \
  --ledger /tmp/ralph-method-2.0-field/.git/ralph-control/events.jsonl \
  --workflow wf_ralph_method_2_0_onda2_hardening --format md

# Live-tail (auto-encerra ao completar)
bash scripts/ralph-live-tail.sh --tick 10

# Observer de anomalias
bash scripts/ralph-anomaly-observer.sh --tick 30

# Diagnóstico read-only (systematic debugging)
php bin/ralph-diagnose.php

# Testes de gating
bash scripts/check-shell.sh && php -l bin/ralph-control
bash scripts/test-ralph-method.sh
```

---

## 5. Open questions / pendências

- **Onde criar `docs/adr/ADR-0033-cursor-promotion.md`** — durante a Phase 2
  da Onda 2, ou PRÉ-execução para já constar no primeiro commit? **Pela
  cadência da Onda 1, durante a fase é o padrão (ADR novo surge com a
  decisão efetiva).**
- **Atualizar `docs/backlog.md`** ao iniciar a Onda 2 para que BL-0005
  fique marcado como "promovido para feature oficial da fila" e novos
  itens (ex.: "REDACTED pipeline no cockpit") sejam adicionados à
  medida que surgirem.
- **Métricas herdadas no observability externo** — o backend Laravel
  (`apps/cockpit/`) não foi atualizado nesta sessão; o relatório de
  métricas (`bin/ralph-time-report.php`) é o único agregado hoje. Se
  houver demanda de UI antes da Onda 3, considerar consumir o relatório
  JSON diretamente.

---

## 6. Resumo em uma frase

**Onda 1 entregue (6/6, 15h08m, 60 commits) · ciclo recovery
alinhado · observer de anomalias no ar · métricas de tempo por feature
como barreira de aceite · plano da Onda 2 (4 features de hardening)
completamente versionado e pronto para `ralph-init apply` na próxima
sessão.**

EOF

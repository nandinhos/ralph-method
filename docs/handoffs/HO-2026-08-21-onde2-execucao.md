# Handoff — HO-2026-08-21-002 · Onda 2 (hardening de segurança) — COMPLETA

> Handoff documental de **transição de sessão**: a Onda 2 foi executada e
> concluída. A próxima sessão abre este arquivo e continua do ponto exato.

---

## 1. Posição final da sessão

**Repositório:** `/home/nandodev/projects/ralph-method` (branch `feat/ralph-method-2.0`)
**Clone de execução:** `/home/nandodev/projects/ralph-method/.field-onda2` (persistente no workspace;
o `/tmp` é efêmero por comando no sandbox)
**Head do principal:** `03f8675` · árvore limpa

### 1.1 Onda 2 — hardening de segurança (COMPLETA, 4/4 features liberadas)

```bash
php bin/ralph-time-report.php \
  --ledger /home/nandodev/projects/ralph-method/.field-onda2/.git/ralph-control/events.jsonl \
  --workflow wf_ralph_method_2_0_onda2_hardening --format md
```

| Feature | Tempo | Implementação | Gates | Debugging | Outros | Attempts | Gates ✅/❌ |
|---|---|---|---|---|---|---|---|
| 102A — sanitize-redact | 2h55m | 55m | 7s | 1h02m | 57m | 9 | 5/2 |
| 102B — cursor-rebaixado | 45m | 12m | 2m43s | 0s | 30m | 2 | 5/0 |
| 102C — policy-failed | 15m22s | 13m34s | 1m48s | 0s | 0s | 1 | 5/0 |
| 102D — event-validation | 11m21s | 9m21s | 2m00s | 0s | 0s | 1 | 5/0 |
| **Total** | **4h07m** | **1h30m** | **6m38s** | **1h02m** | **1h27m** | **13** | **20/2** |

### 1.2 Métricas de aceite (100% atendidas)

- `grep '"cause_kind": *"feature_bug".*policy_violation'` → **0** ✅
- `grep 'secret_detected' reports/` → **0** ✅
- Cursor `promoted=false` (rebaixado; adversarial+hero exigidos) ✅
- `event.rejected` + fuzz 100 tipos entregues pela 102D ✅
- Tempo 102C/102D no ritmo alvo (≤30min); 102A distorceu pelo debug inicial

### 1.3 Commits (20 no principal desde b16af89)

| Tipo | Commits |
|---|---|
| Implementações | `268f6bf` (102A) · `69cba28` (102B) · `7524bcb` (102C) · `5067d8c` (102D) |
| Handoffs | HND-2026-0022..0025 (`.ralph/handoffs/FEATURE-102*/`) |
| ADR | `docs/adr/ADR-0033-cursor-promotion.md` |
| Fixes de harness | `f8a698c` · `d8f63e7` · `3dd1709` · `ece2360` · `cffc54d` · `aa3fea8` · `90fc102` · `28103e4` (+ merges `b3b9959`, `959df1f`) |
| Docs | `docs/reports/relatorio-execucao-onda2.md` · `docs/reports/relatorio-tempo-onda1.md` (base) |

### 1.4 Processos

**Nenhum** (encerrados após `complete`): supervisor, wrapper, live-tail (auto-encerrou),
anomaly-observer. Ledger final: 1556+ eventos.

---

## 2. Lições aprendidas da Onda 2 (novas, além das da Onda 1)

| Lição | Origem | Onde aplicar |
|---|---|---|
| **Provider único definido pelo operador** (codex ponta a ponta) | ANOM-2026-010 | Onda 3+: sem failover automático nem troca no meio |
| agy não opera onde `~/.gemini` é read-only; verify agy via bwrap funciona | ANOM-2026-002 | escolha de provider por ambiente |
| Codex sandbox read-only expõe leitura via `exec` (rg/sed/find), não Read/Glob/Grep | ANOM-2026-006/010 | prompts verify por engine |
| `ralph.sh --verify-only` exige adapter; codex não tem esse modo | ANOM-2026-010 | technical_review codex com script próprio |
| Keys de idempotência com payload mutável (snapshot) colidem | ANOM-2026-007 | nonce (timestamp/random) em recovery/debug |
| Run órfão de supervisor morto segura o flock do supervisor.lock (FD herdado) | observação de fluxo | matar run libera lock; wrapper relança |
| Ciclo recovery automático funcionou na 102B (3 ciclos → debug → retomada sem intervenção) | 102B | o método entrega o que foi projetado |
| `supervise` não lê `test_command` do workflow; gates precisam de comandos explícitos | ANOM-2026-009 | RALPH_QUALITY_COMMAND/RUNTIME_EVIDENCE_CMD/TECHNICAL_REVIEW_COMMAND |

---

## 3. Estado das ferramentas

```bash
# Status do workflow (completo)
php bin/ralph-control status --workflow wf_ralph_method_2_0_onda2_hardening

# Relatório de tempo final
php bin/ralph-time-report.php \
  --ledger /home/nandodev/projects/ralph-method/.field-onda2/.git/ralph-control/events.jsonl \
  --workflow wf_ralph_method_2_0_onda2_hardening --format md

# Relatório de execução (versionado)
cat docs/reports/relatorio-execucao-onda2.md

# Registro de anomalias da onda
cat .onda2-logs/registro-onda2.md
```

---

## 4. Open questions / pendências

- **docs/backlog.md**: atualizar ao iniciar a próxima onda (BL-0005 promovido;
  adicionar "REDACTED pipeline no cockpit" e itens novos).
- **Onda 3** (adapters unificados), 4 (desempenho) e 5 (testes/CI): planejadas no
  `PROJECT-DESCRIPTION.md`; podem lançar features em paralelo via branches isolados.
- **Observability externo** (apps/cockpit): não atualizado nesta onda; o
  `ralph-time-report.php` segue como agregado.

---

## 5. Resumo em uma frase

**Onda 2 entregue (4/4, 4h07m, 20 gates ✅, 10 anomalias corrigidas) com provider
único codex de ponta a ponta, ciclo de recovery automático comprovado e todas as
métricas de aceite atendidas — ~4× mais rápido que a Onda 1 (15h08m) graças aos
fixes herdados e à eliminação das esperas de rate limit.**

EOF
echo "handoff criado"
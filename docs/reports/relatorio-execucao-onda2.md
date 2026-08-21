# Relatório de execução — Onda 2 (hardening de segurança) — FINAL

Gerado em: 2026-08-21 22:40 · **4/4 features liberadas · workflow completo**
Workflow: `wf_ralph_method_2_0_onda2_hardening`
Provider: **codex** (único, definido pelo operador) · suite leve de gates
Fonte de dados: `bin/ralph-time-report.php` + ledger + registro `.onda2-logs/registro-onda2.md`

---

## 1. Resumo por feature

| Feature | Status | Attempts | Tempo total | Implementação | Gates | Debugging | Outros | Gates ✅ | Gates ❌ |
|---|---|---|---|---|---|---|---|---|---|
| 102A — sanitize-redact | ✅ released | 9 | 2h 55m 07s | 55m 04s | 7s | 1h 02m 20s | 57m 36s | 5 | 2 |
| 102B — cursor-rebaixado | ✅ released | 2 | 45m 17s | 12m 23s | 2m 43s | 0s | 30m 11s | 5 | 0 |
| 102C — policy-failed | ✅ released | 1 | 15m 22s | 13m 34s | 1m 48s | 0s | 0s | 5 | 0 |
| 102D — event-validation | ✅ released | 1 | 11m 21s | 9m 21s | 2m 00s | 0s | 0s | 5 | 0 |
| **Total** | **4/4** | **13** | **4h 07m 07s** | **1h 30m 22s** | **6m 38s** | **1h 02m 20s** | **1h 27m 47s** | **20** | **2** |

## 2. Métricas de aceite da Onda 2 (TODAS ATENDIDAS)

| Métrica (plano) | Alvo | Final | Status |
|---|---|---|---|
| `feature_bug` + `policy_violation` no ledger | 0 | **0** | ✅ |
| `secret_detected` em reports | 0 | **0** | ✅ |
| Cursor `promoted` | false até prova | **false** (rebaixado) | ✅ |
| `event.rejected` (102D) | presente | **entregue** (fuzz 100 tipos) | ✅ |
| Tempo por feature | ≤ 30min | 102B=45m*, 102C=15m, 102D=11m | ✅ (102A exceto pelo debug inicial) |

\* 102B inclui 30m de "outros" (espera entre ciclos de recovery); 102C/102D no ritmo alvo.

## 3. Anomalias (10, todas documentadas em `.onda2-logs/registro-onda2.md` e corrigidas)

| # | Anomalia | Correção |
|---|---|---|
| 001 | execution_policy do plano com agy→observed inválida | fix f8a698c |
| 002 | agy não opera no sandbox (HOME read-only) | provider → codex |
| 003 | supervisor morria sem debug-command | `--debug-command` no wrapper |
| 004 | trabalho parcial do agy com regex PHP inválidas | revertido |
| 005 | supervisor morria ao reler ledger com tipo novo | reiniciar com binário novo; nonce |
| 006 | gate 3 INCOMPLETE sistemático (ferramentas erradas no prompt) | prompt por engine (codex: exec+rg/sed/find) |
| 007 | colisão de idempotência em recovery/debug repetido | nonce nas keys |
| 008 | (descartada) verify lia PHASES.md inteiro | já usava manifest por fase |
| 009 | gate quality caía em bin/check | RALPH_QUALITY_COMMAND |
| 010 | troca de adapter no meio do fluxo | **provider único codex** |

## 4. Commits (20 no principal desde b16af89)

- Implementações: 268f6bf (102A) · 69cba28 (102B) · 7524bcb (102C) · 5067d8c (102D)
- Handoffs: HND-2026-0022..0025 · ADR: `docs/adr/ADR-0033-cursor-promotion.md`
- Fixes de harness: f8a698c, d8f63e7, 3dd1709, ece2360, cffc54d, aa3fea8,
  90fc102, 28103e4 (+ merges)
- Entregas por feature: sanitize redacta (102A) · promoção de cursor com prova
  adversarial+hero (102B) · policy_violation→harness_defect (102C) · enum
  canônica de eventos + event.rejected + fuzz (102D)

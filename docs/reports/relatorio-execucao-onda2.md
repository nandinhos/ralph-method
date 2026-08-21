# Relatório de execução — Onda 2 (hardening de segurança)

Gerado em: 2026-08-21 22:35 (parcial — 3/4 features liberadas, 102D em execução)
Workflow: `wf_ralph_method_2_0_onda2_hardening`
Provider: **codex** (único, definido pelo operador) · suite leve de gates
Fonte de dados: `bin/ralph-time-report.php` + ledger + registro `.onda2-logs/registro-onda2.md`

---

## 1. Resumo por feature

| Feature | Status | Attempts | Tempo total | Implementação | Gates | Debugging | Outros/esperas | Gates ✅ | Gates ❌ |
|---|---|---|---|---|---|---|---|---|---|
| 102A — sanitize-redact | ✅ released | 9 | 2h 55m | 55m | 7s | 1h 02m | 57m | 5 | 2 |
| 102B — cursor-rebaixado | ✅ released | 2 | 45m | 12m | 2m 43s | 0s | 30m | 5 | 0 |
| 102C — policy-failed | ✅ released | 1 | 15m | 13m | 1m 48s | 0s | 0s | 5 | 0 |
| 102D — event-validation | 🔄 em execução | 1 | 5m+ | — | — | — | — | 0 | 0 |
| **Total (3/4)** | — | **13** | **4h 01m** | **1h 21m** | **4m 38s** | **1h 02m** | **1h 33m** | **15** | **2** |

## 2. Métricas de aceite da Onda 2

| Métrica (definida no plano) | Alvo | Valor atual | Status |
|---|---|---|---|
| `feature_bug` + `policy_violation` no ledger | 0 | **0** | ✅ |
| `secret_detected` em reports | 0 | **0** | ✅ |
| Cursor `promoted` | false até prova | **false** | ✅ (rebaixado, correto) |
| `event.rejected` registrado (102D) | presente no fim | 0 (fase ainda rodando) | ⏳ |
| Tempo médio por feature | ≤ 30min | 102B=45m, 102C=**15m** | ⏳ 102A distorceu |

## 3. Anomalias encontradas (10, todas documentadas e corrigidas)

| # | Anomalia | Correção |
|---|---|---|
| 001 | execution_policy do plano com agy→observed inválida | fix f8a698c (plano) |
| 002 | agy não opera no sandbox (HOME read-only) | provider → codex |
| 003 | supervisor morria sem debug-command | `--debug-command` no wrapper |
| 004 | trabalho parcial do agy com regex PHP inválidas | revertido (árvore limpa) |
| 005 | supervisor morria ao reler ledger com tipo novo (self-hosting) | reiniciar com binário novo; nonce |
| 006 | gate 3 (verify) INCOMPLETE sistemático (ferramentas erradas no prompt) | prompt por engine (codex: exec+rg/sed/find) |
| 007 | colisão de idempotência em recovery/debug repetido | nonce (timestamp/random) nas keys |
| 008 | (descartada) verify lia PHASES.md inteiro | já usava manifest por fase |
| 009 | gate quality caía em bin/check (inexistente) | RALPH_QUALITY_COMMAND (suite leve) |
| 010 | troca de adapter no meio do fluxo | **provider único codex de ponta a ponta** |

## 4. Commits

- 18 commits desde b16af89 (9 fixes + 3 implementações + 3 handoffs + merge)
- Implementações: 268f6bf (102A), 69cba28 (102B), 7524bcb (102C)
- Handoffs: HND-2026-0022 (102A), 6e6b2f8 (102B), a47b744 (102C)
- ADR criado: `docs/adr/ADR-0033-cursor-promotion.md`

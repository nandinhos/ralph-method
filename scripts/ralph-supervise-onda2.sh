#!/usr/bin/env bash
#
# ralph-supervise-onda2.sh — supervisor da Onda 2 (hardening de segurança).
#
# Lança o ralph-control supervise para o workflow wf_ralph_method_2_0_onda2_hardening
# no clone de execução persistente, com a suite leve de gates (check-shell +
# test-ralph-method) em vez do ci-portable (release).
#
# Engine primário: codex (runner nativo, perfil .ralph/codex.env) com
# CODEX_HOME redirecionado para o workspace — o agy não opera no sandbox
# (HOME read-only), anomalia ANOM-2026-002 documentada no registro da onda.
#
# Somente o supervisor roda aqui: ele é a única autoridade de transição do
# ledger. Este script não aprova gates nem escolhe a próxima feature.
#
# Uso (lançado pelo orquestrador em 2º plano):
#   nohup bash scripts/ralph-supervise-onda2.sh > logs/supervise-onda2.log 2>&1 &
#
# Variáveis de ambiente (com defaults deste checkout):
#   RALPH_FIELD       clone de execução (default: raiz do repo)
#   RALPH_WORKFLOW    workflow da Onda 2
#   RALPH_ENGINE      engine primário (default: codex)
#   RALPH_TEST_CMD    suite leve de gates
#   RALPH_INTERVAL    intervalo do supervisor em segundos
#   RALPH_MAX_RETRIES limite de retries do supervisor

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELD="${RALPH_FIELD:-$ROOT}"
WORKFLOW="${RALPH_WORKFLOW:-wf_ralph_method_2_0_onda2_hardening}"
ENGINE="${RALPH_ENGINE:-codex}"
TEST_CMD="${RALPH_TEST_CMD:-bash scripts/check-shell.sh && bash scripts/test-ralph-method.sh}"
INTERVAL="${RALPH_INTERVAL:-30}"
MAX_RETRIES="${RALPH_MAX_RETRIES:-3}"
DEBUG_CMD="${RALPH_DEBUG_COMMAND:-php bin/ralph-diagnose.php}"
CODEX_HOME="${CODEX_HOME:-$ROOT/.onda2-home/.codex}"

cd "$FIELD" || exit 2

echo "[supervise-onda2] workflow=$WORKFLOW engine=$ENGINE field=$FIELD intervalo=${INTERVAL}s"
echo "[supervise-onda2] test-cmd: $TEST_CMD"
echo "[supervise-onda2] debug-cmd: $DEBUG_CMD"
echo "[supervise-onda2] CODEX_HOME=$CODEX_HOME"

export CODEX_HOME

# Comandos explícitos dos gates (o wrapper default de quality cai em bin/check,
# inexistente no self-hosting; runtime_evidence e technical_review usam os
# scripts self-host read-only do próprio método — ANOM-2026-009).
export RALPH_QUALITY_COMMAND="${RALPH_QUALITY_COMMAND:-bash scripts/check-shell.sh && bash scripts/test-ralph-method.sh}"
export RALPH_RUNTIME_EVIDENCE_CMD="${RALPH_RUNTIME_EVIDENCE_CMD:-bash scripts/ralph-selfhost-runtime-evidence.sh}"
export RALPH_TECHNICAL_REVIEW_COMMAND="${RALPH_TECHNICAL_REVIEW_COMMAND:-bash scripts/ralph-selfhost-technical-review.sh}"
# O --verify-only do ralph.sh exige engine com adapter (opencode/agy/cursor);
# o agy verify roda via bwrap com mounts controlados e funciona no sandbox
# (comprovado), enquanto o impl agy não opera (ANOM-2026-002). O impl da
# feature continua codex via --engine explícito no supervise.
export RALPH_ENGINE="${RALPH_ENGINE:-agy}"

# O ralph-control supervise retorna em estados de espera (debugging_running,
# capacity_wait, recovery_required etc.) — o wrapper relança até o workflow
# completar, respeitando o lock do supervisor entre execuções.
ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[supervise-onda2] ciclo $ATTEMPT em $(date '+%H:%M:%S')"
  php "$FIELD/bin/ralph-control" supervise \
    --workflow "$WORKFLOW" \
    --engine "$ENGINE" \
    --test-cmd "$TEST_CMD" \
    --debug-command "$DEBUG_CMD" \
    --interval "$INTERVAL" \
    --max-retries "$MAX_RETRIES"
  RC=$?
  # Exit 0 com workflow completo: encerra o wrapper.
  if [ "$RC" -eq 0 ] && php "$FIELD/bin/ralph-control" status --workflow "$WORKFLOW" 2>/dev/null \
      | grep -q '"complete"'; then
    echo "[supervise-onda2] workflow completo; encerrando wrapper"
    exit 0
  fi
  sleep "${RALPH_RELAUNCH_SLEEP:-5}"
done

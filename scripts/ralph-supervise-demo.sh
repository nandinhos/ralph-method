#!/usr/bin/env bash
#
# ralph-supervise-demo.sh — supervisor da demonstração do loop no
# projeto teste-events-opencode (campo .field-demo).
#
# Provider único: codex (runner nativo) com CODEX_HOME no workspace —
# mesmo padrão validado na Onda 2 (o agy não opera onde ~/.gemini é
# read-only; codex roda com CODEX_HOME redirecionado).
#
# Gate quality focado: o workflow demo usa o filtro HealthDemoTest
# (docker compose exec) para não esbarrar no baseline de 4 testes
# pré-existentes de outras fatias.
#
# Somente o supervisor roda aqui: autoridade única do ledger; não aprova
# gates nem escolhe a próxima feature.
#
# Uso (orquestrador em 2º plano):
#   nohup bash scripts/ralph-supervise-demo.sh > logs/supervise-demo.log 2>&1 &

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELD="${RALPH_DEMO_FIELD:-$ROOT/.field-demo}"
WORKFLOW="${RALPH_DEMO_WORKFLOW:-wf_demo_ralph_loop_health}"
ENGINE="${RALPH_ENGINE:-codex}"
TEST_CMD="${RALPH_TEST_CMD:-docker compose exec -T app php artisan test --compact --filter=HealthDemoTest}"
INTERVAL="${RALPH_INTERVAL:-20}"
MAX_RETRIES="${RALPH_MAX_RETRIES:-3}"
DEBUG_CMD="${RALPH_DEBUG_COMMAND:-php bin/ralph-diagnose.php}"

cd "$FIELD" || exit 2

echo "[supervise-demo] workflow=$WORKFLOW engine=$ENGINE field=$FIELD"
echo "[supervise-demo] test-cmd: $TEST_CMD"

# Provider único: codex com CODEX_HOME no workspace + variáveis do perfil.
export CODEX_HOME="${CODEX_HOME:-$ROOT/.onda2-home/.codex}"
export RALPH_CODEX_PROFILE="${RALPH_CODEX_PROFILE:-bc-harness}"
export RALPH_CODEX_MODEL="${RALPH_CODEX_MODEL:-gpt-5.6-luna}"
export RALPH_CODEX_REASONING_EFFORT="${RALPH_CODEX_REASONING_EFFORT:-high}"
export RALPH_VERIFY_MODEL="${RALPH_VERIFY_MODEL:-gpt-5.6-luna}"

# Comandos dos gates (qualidade focado + self-host read-only). Os scripts
# self-host (runtime_evidence, technical_review codex, diagnose) vivem no
# ralph-method; o campo .field-demo tem só o núcleo instalado do método.
export RALPH_QUALITY_COMMAND="${RALPH_QUALITY_COMMAND:-$TEST_CMD}"
export RALPH_RUNTIME_EVIDENCE_CMD="${RALPH_RUNTIME_EVIDENCE_CMD:-bash $ROOT/scripts/ralph-selfhost-runtime-evidence.sh}"
export RALPH_TECHNICAL_REVIEW_COMMAND="${RALPH_TECHNICAL_REVIEW_COMMAND:-bash $ROOT/scripts/ralph-selfhost-technical-review-codex.sh}"
DEBUG_CMD="${RALPH_DEBUG_COMMAND:-php $ROOT/bin/ralph-diagnose.php}"

# Wrapper com relançamento até completar (padrão Onda 2).
ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[supervise-demo] ciclo $ATTEMPT em $(date '+%H:%M:%S')"
  php "$FIELD/bin/ralph-control" supervise \
    --workflow "$WORKFLOW" \
    --engine "$ENGINE" \
    --test-cmd "$TEST_CMD" \
    --debug-command "$DEBUG_CMD" \
    --interval "$INTERVAL" \
    --max-retries "$MAX_RETRIES"
  RC=$?
  if [ "$RC" -eq 0 ] && php "$FIELD/bin/ralph-control" status --workflow "$WORKFLOW" 2>/dev/null \
      | grep -q '"complete"'; then
    echo "[supervise-demo] workflow completo; encerrando wrapper"
    exit 0
  fi
  sleep "${RALPH_RELAUNCH_SLEEP:-8}"
done

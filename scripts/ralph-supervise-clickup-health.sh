#!/usr/bin/env bash
#
# ralph-supervise-clickup-health.sh — supervisor da feature "SAÚDE CLICKUP"
# (projeto teste-events-opencode, campo .field-clickup-health).
#
# Provider único: codex (runner nativo) com CODEX_HOME no workspace — mesmo
# padrão validado na Onda 2 e na demo.
#
# Gate quality focado: filter=ClickUpHealthTest (o projeto tem baseline de
# 4 testes pré-existentes falhando de outras fatias).
#
# Somente o supervisor roda aqui: autoridade única do ledger; não aprova
# gates nem escolhe a próxima feature.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELD="${RALPH_CLICKUP_FIELD:-$ROOT/.field-clickup-health}"
WORKFLOW="${RALPH_CLICKUP_WORKFLOW:-wf_clickup_health_dashboard}"
ENGINE="${RALPH_ENGINE:-codex}"
TEST_CMD="${RALPH_TEST_CMD:-docker compose --env-file .env.docker -p events_clickup_field exec -T app php artisan test --compact --filter=ClickUpHealthTest}"
INTERVAL="${RALPH_INTERVAL:-20}"
MAX_RETRIES="${RALPH_MAX_RETRIES:-3}"
DEBUG_CMD="${RALPH_DEBUG_COMMAND:-php $ROOT/bin/ralph-diagnose.php}"

cd "$FIELD" || exit 2

echo "[supervise-clickup-health] workflow=$WORKFLOW engine=$ENGINE field=$FIELD"
echo "[supervise-clickup-health] test-cmd: $TEST_CMD"

export CODEX_HOME="${CODEX_HOME:-$ROOT/.onda2-home/.codex}"
export RALPH_CODEX_PROFILE="${RALPH_CODEX_PROFILE:-bc-harness}"
export RALPH_CODEX_MODEL="${RALPH_CODEX_MODEL:-gpt-5.6-luna}"
export RALPH_CODEX_REASONING_EFFORT="${RALPH_CODEX_REASONING_EFFORT:-high}"
export RALPH_VERIFY_MODEL="${RALPH_VERIFY_MODEL:-gpt-5.6-luna}"

export RALPH_QUALITY_COMMAND="${RALPH_QUALITY_COMMAND:-$TEST_CMD}"
export RALPH_RUNTIME_EVIDENCE_CMD="${RALPH_RUNTIME_EVIDENCE_CMD:-bash $ROOT/scripts/ralph-selfhost-runtime-evidence.sh}"
export RALPH_TECHNICAL_REVIEW_COMMAND="${RALPH_TECHNICAL_REVIEW_COMMAND:-bash $ROOT/scripts/ralph-selfhost-technical-review-codex.sh}"

ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[supervise-clickup-health] ciclo $ATTEMPT em $(date '+%H:%M:%S')"
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
    echo "[supervise-clickup-health] workflow completo; encerrando wrapper"
    exit 0
  fi
  sleep "${RALPH_RELAUNCH_SLEEP:-8}"
done

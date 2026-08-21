#!/usr/bin/env bash
#
# ralph-supervise-onda2.sh — supervisor da Onda 2 (hardening de segurança).
#
# LANÇA o ralph-control supervise para o workflow wf_ralph_method_2_0_onda2_hardening
# no clone de execução persistente, com o provider DEFINIDO PELO OPERADOR
# (default: codex) para TODO o fluxo — implementação, gates e revisão.
# Sem failover automático: se o provider definido falhar, o supervisor
# registra recovery/debug e o orquestrador decide; não troca de provider
# silenciosamente (ANOM-2026-002/010).
#
# O workflow.json já congela provider_chain=[codex] (operador define o
# provider; o ralph executa tudo com ele).
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
#   RALPH_ENGINE      provider do fluxo inteiro (default: codex)
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

cd "$FIELD" || exit 2

echo "[supervise-onda2] workflow=$WORKFLOW engine=$ENGINE field=$FIELD intervalo=${INTERVAL}s"
echo "[supervise-onda2] test-cmd: $TEST_CMD"
echo "[supervise-onda2] debug-cmd: $DEBUG_CMD"

# Provider único do fluxo: codex (runner nativo) com CODEX_HOME no workspace
# (o agy não opera no sandbox — ANOM-2026-002). O operador define o provider;
# o ralph executa tudo com ele, sem trocar.
export CODEX_HOME="${CODEX_HOME:-$ROOT/.onda2-home/.codex}"

# Comandos explícitos dos gates, todos com o mesmo provider (codex):
# - quality: suite leve (o default bin/check não existe no self-hosting);
# - runtime_evidence: script self-host read-only;
# - technical_review: script codex read-only (mesmo mecanismo do gate 3 do
#   bloco; o ralph.sh --verify-only exige adapter e não se aplica ao codex).
export RALPH_QUALITY_COMMAND="${RALPH_QUALITY_COMMAND:-bash scripts/check-shell.sh && bash scripts/test-ralph-method.sh}"
export RALPH_RUNTIME_EVIDENCE_CMD="${RALPH_RUNTIME_EVIDENCE_CMD:-bash scripts/ralph-selfhost-runtime-evidence.sh}"
export RALPH_TECHNICAL_REVIEW_COMMAND="${RALPH_TECHNICAL_REVIEW_COMMAND:-bash scripts/ralph-selfhost-technical-review-codex.sh}"

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
  sleep "${RALPH_RELAUNCH_SLEEP:-10}"
done

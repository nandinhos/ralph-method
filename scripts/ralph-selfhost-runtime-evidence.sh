#!/usr/bin/env bash
#
# ralph-selfhost-runtime-evidence.sh — gate runtime_evidence do self-hosting.
#
# Evidência de runtime do próprio método: o controlador responde, o ledger está
# íntegro e o workflow está consistente. Somente leitura; não grava estado.
#
# Uso (invocado pelo supervisor):
#   RALPH_RUNTIME_EVIDENCE_CMD=bash scripts/ralph-selfhost-runtime-evidence.sh

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"

if [ -z "$WORKFLOW" ]; then
  echo "contexto ausente: RALPH_WORKFLOW_ID é obrigatório" >&2
  exit 2
fi

cd "$REPO" || exit 2
STATUS="$(php bin/ralph-control status --workflow "$WORKFLOW" 2>&1)"
STATUS_RC=$?
if [ "$STATUS_RC" -ne 0 ]; then
  echo "controlador não respondeu: $STATUS" >&2
  exit 1
fi

printf 'runtime_evidence: controlador respondeu; workflow=%s eventos=%s\n' \
  "$WORKFLOW" \
  "$(printf '%s' "$STATUS" | php -r '$d=json_decode(stream_get_contents(STDIN), true); echo $d["event_count"] ?? "n/d";')"
# Verifica a integridade do ledger (hash chain) — fail-closed se corrompido.
php bin/ralph-control verify --workflow "$WORKFLOW" >/dev/null 2>&1 || {
  echo "ledger com hash chain inválida" >&2
  exit 1
}
exit 0

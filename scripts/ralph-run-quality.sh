#!/usr/bin/env bash

# ralph-run-quality.sh — gate quality (comando canônico instalado pelo método).
#
# Contrato nativo (v0.9.0+): quando invocado pelo supervisor (ralph-control
# supervise), o contexto chega por ambiente e o wrapper apenas roda o comando
# de qualidade e emite o exit code — o controlador registra o gate. A chamada
# manual com argumentos posicionais continua aceita e registra o gate.
#
# Ambiente (modo supervisor):
#   RALPH_WORKFLOW_ID  RALPH_FEATURE_KEY  RALPH_ATTEMPT  RALPH_GATE
#   RALPH_REPORT_PATH  RALPH_LEASE
#
# Argumentos (modo manual, compatível com versões anteriores):
#   --workflow ID --feature KEY --lease TOKEN [--command CMD]

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"
FEATURE="${RALPH_FEATURE_KEY:-}"
LEASE="${RALPH_LEASE:-}"
GATE="${RALPH_GATE:-}"
COMMAND=""
SUPERVISOR=0
# O supervisor exporta RALPH_GATE no contrato por ambiente; a presença dela
# indica invocação controlada (o controlador registra o gate). Chamada manual
# com --workflow/--feature/--lease registra o gate como antes.
[ -n "$GATE" ] && SUPERVISOR=1
[ -n "$GATE" ] || GATE="quality"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    *) echo "uso: ralph-run-quality.sh [--workflow ID --feature KEY --lease TOKEN [--command CMD]]" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ]; then
  echo "workflow e feature são obrigatórios (via RALPH_WORKFLOW_ID/RALPH_FEATURE_KEY ou --workflow/--feature)" >&2
  exit 2
fi
if [ "$SUPERVISOR" -eq 0 ] && [ -z "$LEASE" ]; then
  echo "lease é obrigatório no modo manual (--lease)" >&2
  exit 2
fi

[ -n "$COMMAND" ] || COMMAND="bin/check"
if [ ! -f "$REPO/$COMMAND" ]; then
  if ! command -v "$COMMAND" >/dev/null 2>&1; then
    echo "comando de qualidade ausente: $COMMAND (crie bin/check ou passe --command)" >&2
    exit 1
  fi
fi

set +e
(cd "$REPO" && bash -c "$COMMAND") 2>&1
EXIT_CODE=$?
set -e

if [ "$SUPERVISOR" -eq 1 ]; then
  exit "$EXIT_CODE"
fi

GIT_DIR="$(git -C "$REPO" rev-parse --git-common-dir)"
REPORT_DIR="$GIT_DIR/ralph-control/reports"
mkdir -p "$REPORT_DIR"
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope quality --plain)"
REPORT="$REPORT_DIR/${DOCUMENT_ID}.log"

if [ "$EXIT_CODE" -eq 0 ]; then
  STATUS=passed
else
  STATUS=rejected
fi

"$CONTROL" gate \
  --workflow "$WORKFLOW" \
  --feature "$FEATURE" \
  --lease "$LEASE" \
  --gate quality \
  --status "$STATUS" \
  --exit-code "$EXIT_CODE" \
  --artifact "artifact_${FEATURE}_quality" \
  --document-id "$DOCUMENT_ID" \
  --report-path "$REPORT" \
  --producer quality-runner

exit "$EXIT_CODE"

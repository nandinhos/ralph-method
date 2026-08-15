#!/usr/bin/env bash

# ralph-run-runtime-evidence.sh — gate runtime_evidence (comando canônico
# instalado pelo método).
#
# Contrato nativo (v0.9.0+): o supervisor (ralph-control supervise) chama este
# wrapper sem argumentos posicionais e fornece o contexto por ambiente; o
# wrapper roda a evidência de runtime e emite o exit code — o controlador
# registra o gate. A chamada manual com argumentos posicionais continua aceita
# e registra o gate.
#
# Ambiente (modo supervisor):
#   RALPH_WORKFLOW_ID  RALPH_FEATURE_KEY  RALPH_ATTEMPT  RALPH_GATE
#   RALPH_REPORT_PATH  RALPH_LEASE  RALPH_RUNTIME_EVIDENCE_CMD
#
# Argumentos (modo manual, compatível com versões anteriores):
#   --workflow ID --feature KEY --lease TOKEN [--command CMD]
#
# Comando de evidência (primeira regra que resolver):
#   1. RALPH_RUNTIME_EVIDENCE_CMD / --command
#   2. primeiro executável scripts/*runtime-evidence*  (detecção)
#   3. bin/check (suíte do projeto como evidência de runtime mínima)

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"
FEATURE="${RALPH_FEATURE_KEY:-}"
LEASE="${RALPH_LEASE:-}"
GATE="${RALPH_GATE:-runtime_evidence}"
COMMAND="${RALPH_RUNTIME_EVIDENCE_CMD:-}"
SUPERVISOR=0
[ -n "$GATE" ] && SUPERVISOR=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    *) echo "uso: ralph-run-runtime-evidence.sh [--workflow ID --feature KEY --lease TOKEN [--command CMD]]" >&2; exit 2 ;;
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

if [ -z "$COMMAND" ]; then
  DETECTED="$(find "$REPO/scripts" -maxdepth 1 -type f -name '*runtime-evidence*' -executable 2>/dev/null | head -1 || true)"
  [ -n "$DETECTED" ] && COMMAND="$DETECTED"
fi
if [ -z "$COMMAND" ] && [ -f "$REPO/bin/check" ]; then
  COMMAND="bin/check"
fi

if [ -z "$COMMAND" ]; then
  echo "nenhuma evidência de runtime configurada: defina RALPH_RUNTIME_EVIDENCE_CMD, scripts/*runtime-evidence* ou bin/check" >&2
  exit 1
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
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope runtime-evidence --plain)"
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
  --gate runtime_evidence \
  --status "$STATUS" \
  --exit-code "$EXIT_CODE" \
  --artifact "artifact_${FEATURE}_runtime" \
  --document-id "$DOCUMENT_ID" \
  --report-path "$REPORT" \
  --producer runtime-evidence-runner

exit "$EXIT_CODE"

#!/usr/bin/env bash

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW=""
FEATURE=""
LEASE=""
COMMAND="${RALPH_RUNTIME_EVIDENCE_CMD:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    *) echo "uso: ralph-run-runtime-evidence.sh --workflow ID --feature KEY --lease TOKEN --command CMD" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ] || [ -z "$LEASE" ]; then
  echo "workflow, feature e lease são obrigatórios" >&2
  exit 2
fi

GIT_DIR="$(git -C "$REPO" rev-parse --git-common-dir)"
REPORT_DIR="$GIT_DIR/ralph-control/reports"
mkdir -p "$REPORT_DIR"
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope runtime-evidence --plain)"
REPORT="$REPORT_DIR/${DOCUMENT_ID}.log"

if [ -z "$COMMAND" ]; then
  echo "nenhum comando de runtime evidence foi configurado" >"$REPORT"
  "$CONTROL" gate \
    --workflow "$WORKFLOW" \
    --feature "$FEATURE" \
    --lease "$LEASE" \
    --gate runtime_evidence \
    --status rejected \
    --artifact "artifact_${FEATURE}_runtime" \
    --document-id "$DOCUMENT_ID" \
    --report-path "$REPORT" \
    --producer runtime-evidence-runner
  exit 1
fi

set +e
(cd "$REPO" && bash -lc "$COMMAND") >"$REPORT" 2>&1
EXIT_CODE=$?
set -e

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

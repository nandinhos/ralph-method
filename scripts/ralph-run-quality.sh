#!/usr/bin/env bash

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW=""
FEATURE=""
LEASE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    *) echo "uso: ralph-run-quality.sh --workflow ID --feature KEY --lease TOKEN" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ] || [ -z "$LEASE" ]; then
  echo "workflow, feature e lease são obrigatórios" >&2
  exit 2
fi

GIT_DIR="$(git -C "$REPO" rev-parse --git-common-dir)"
REPORT_DIR="$GIT_DIR/ralph-control/reports"
mkdir -p "$REPORT_DIR"
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope quality --plain)"
REPORT="$REPORT_DIR/${DOCUMENT_ID}.log"

set +e
(cd "$REPO" && bin/check) >"$REPORT" 2>&1
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
  --gate quality \
  --status "$STATUS" \
  --exit-code "$EXIT_CODE" \
  --artifact "artifact_${FEATURE}_quality" \
  --document-id "$DOCUMENT_ID" \
  --report-path "$REPORT" \
  --producer quality-runner

exit "$EXIT_CODE"

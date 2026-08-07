#!/usr/bin/env bash

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW=""
FEATURE=""
LEASE=""
GATE=""
COMMAND=""
PRODUCER="independent-reviewer"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --producer) PRODUCER="$2"; shift 2 ;;
    *) echo "uso: ralph-run-independent-gate.sh --workflow ID --feature KEY --lease TOKEN --gate technical_review|curation --command CMD" >&2; exit 2 ;;
  esac
done

case "$GATE" in
  technical_review|curation) ;;
  *) echo "gate independente inválido: $GATE" >&2; exit 2 ;;
esac

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ] || [ -z "$LEASE" ] || [ -z "$COMMAND" ]; then
  echo "workflow, feature, lease e command são obrigatórios" >&2
  exit 2
fi

GIT_DIR="$(git -C "$REPO" rev-parse --git-common-dir)"
REPORT_DIR="$GIT_DIR/ralph-control/reports"
mkdir -p "$REPORT_DIR"
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope "$GATE" --plain)"
REPORT="$REPORT_DIR/${DOCUMENT_ID}.log"
BEFORE="$(git -C "$REPO" status --porcelain)"

set +e
(cd "$REPO" && bash -lc "$COMMAND") >"$REPORT" 2>&1
EXIT_CODE=$?
set -e

AFTER="$(git -C "$REPO" status --porcelain)"
STATUS=passed
if [ "$EXIT_CODE" -ne 0 ] || [ "$BEFORE" != "$AFTER" ]; then
  STATUS=rejected
fi
if [ "$BEFORE" != "$AFTER" ] && [ "$EXIT_CODE" -eq 0 ]; then
  EXIT_CODE=1
fi

"$CONTROL" gate \
  --workflow "$WORKFLOW" \
  --feature "$FEATURE" \
  --lease "$LEASE" \
  --gate "$GATE" \
  --status "$STATUS" \
  --exit-code "$EXIT_CODE" \
  --artifact "artifact_${FEATURE}_${GATE}" \
  --document-id "$DOCUMENT_ID" \
  --report-path "$REPORT" \
  --producer "$PRODUCER"

if [ "$BEFORE" != "$AFTER" ]; then
  echo "o produtor independente alterou a árvore; gate rejeitado" >&2
fi

exit "$EXIT_CODE"

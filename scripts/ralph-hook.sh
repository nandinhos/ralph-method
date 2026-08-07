#!/usr/bin/env bash

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"

if [ ! -x "$CONTROL" ]; then
  exit 0
fi

# O hook só observa. O Ralph upstream ignora falha do hook por contrato; por
# isso a ausência de contexto não pode transformar observabilidade em decisão.
"$CONTROL" observe \
  --workflow "${RALPH_WORKFLOW_ID:-}" \
  --feature "${RALPH_FEATURE_KEY:-}" \
  --event "${RALPH_EVENT:-${1:-unknown}}" \
  --detail "${RALPH_EVENT_DETAIL:-${2:-}}" \
  >/dev/null 2>&1 || true

exit 0

#!/usr/bin/env bash

# ralph-run-independent-gate.sh — gates technical_review e curation (comando
# canônico instalado pelo método).
#
# Contrato nativo (v0.9.0+): o supervisor (ralph-control supervise) chama este
# wrapper sem argumentos posicionais e fornece o contexto por ambiente
# (incluindo RALPH_GATE e RALPH_TECHNICAL_REVIEW_COMMAND /
# RALPH_CURATION_COMMAND); o wrapper roda a revisão/ curadoria e emite o exit
# code — o controlador registra o gate. A chamada manual com argumentos
# posicionais continua aceita e registra o gate.
#
# Ambiente (modo supervisor):
#   RALPH_WORKFLOW_ID  RALPH_FEATURE_KEY  RALPH_ATTEMPT  RALPH_GATE
#   RALPH_REPORT_PATH  RALPH_LEASE
#   RALPH_TECHNICAL_REVIEW_COMMAND | RALPH_CURATION_COMMAND
#
# Argumentos (modo manual, compatível com versões anteriores):
#   --workflow ID --feature KEY --lease TOKEN --gate technical_review|curation
#   [--command CMD] [--producer PROD]
#
# Comando do gate (primeira regra que resolver):
#   1. env RALPH_<GATE>_COMMAND / --command
#   2. para curation: bin/ralph-knowledge (curadoria de conhecimento)
#   3. sem comando: o wrapper não inventa revisão; emite exit 1 (rejeitado)

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/bin/ralph-control"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"
FEATURE="${RALPH_FEATURE_KEY:-}"
LEASE="${RALPH_LEASE:-}"
GATE="${RALPH_GATE:-}"
COMMAND=""
PRODUCER="independent-reviewer"
SUPERVISOR=0
[ -n "$GATE" ] && SUPERVISOR=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --lease) LEASE="$2"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --producer) PRODUCER="$2"; shift 2 ;;
    *) echo "uso: ralph-run-independent-gate.sh --workflow ID --feature KEY --lease TOKEN --gate technical_review|curation [--command CMD]" >&2; exit 2 ;;
  esac
done

[ -n "$GATE" ] || GATE="${RALPH_GATE:-}"

case "$GATE" in
  technical_review|curation) ;;
  *) echo "gate independente inválido: $GATE" >&2; exit 2 ;;
esac

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ]; then
  echo "workflow e feature são obrigatórios (via RALPH_WORKFLOW_ID/RALPH_FEATURE_KEY ou --workflow/--feature)" >&2
  exit 2
fi
if [ "$SUPERVISOR" -eq 0 ] && [ -z "$LEASE" ]; then
  echo "lease é obrigatório no modo manual (--lease)" >&2
  exit 2
fi

ENV_NAME="RALPH_$(echo "$GATE" | tr '[:lower:]' '[:upper:]')_COMMAND"
[ -n "$COMMAND" ] || COMMAND="${!ENV_NAME:-}"
if [ -z "$COMMAND" ] && [ "$GATE" = "curation" ] && [ -x "$REPO/bin/ralph-knowledge" ]; then
  # FEATURE-096/097: o default de curation pré-release é READ-ONLY (lista
  # candidatos e confirma que nada bloqueia a entrega); a decisão de retenção
  # acontece pós-release. Sem ação obrigatória o ralph-knowledge sairia 2.
  COMMAND="bin/ralph-knowledge candidates --workflow \"$WORKFLOW\" --feature \"$FEATURE\""
fi

BEFORE="$(git -C "$REPO" status --porcelain)"

set +e
if [ -z "$COMMAND" ]; then
  echo "nenhum comando configurado para o gate $GATE (defina $ENV_NAME ou --command)" >&2
  EXIT_CODE=1
else
  (cd "$REPO" && bash -c "$COMMAND") 2>&1
  EXIT_CODE=$?
fi
set -e

AFTER="$(git -C "$REPO" status --porcelain)"
if [ "$BEFORE" != "$AFTER" ] && [ "$EXIT_CODE" -eq 0 ]; then
  echo "o produtor do gate $GATE alterou a árvore; gate rejeitado" >&2
  EXIT_CODE=1
fi

if [ "$SUPERVISOR" -eq 1 ]; then
  exit "$EXIT_CODE"
fi

GIT_DIR="$(git -C "$REPO" rev-parse --git-common-dir)"
REPORT_DIR="$GIT_DIR/ralph-control/reports"
mkdir -p "$REPORT_DIR"
DOCUMENT_ID="$($CONTROL document-id --kind RPT --workflow "$WORKFLOW" --feature "$FEATURE" --scope "$GATE" --plain)"
REPORT="$REPORT_DIR/${DOCUMENT_ID}.log"

STATUS=passed
if [ "$EXIT_CODE" -ne 0 ] || [ "$BEFORE" != "$AFTER" ]; then
  STATUS=rejected
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

exit "$EXIT_CODE"

#!/usr/bin/env bash
#
# ralph-selfhost-technical-review.sh — gate technical_review do self-hosting.
#
# Revisão técnica independente read-only do código da feature usando o próprio
# ralph.sh no modo --verify-only com o engine OpenCode e o agente ralph-review
# (a mesma revisão read-only do fluxo normal). O contexto chega por ambiente
# (contrato do supervisor: RALPH_WORKFLOW_ID, RALPH_FEATURE_KEY, RALPH_ATTEMPT,
# RALPH_GATE, RALPH_REPORT_PATH). Não grava estado global; somente leitura.
#
# Uso (invocado pelo supervisor):
#   RALPH_TECHNICAL_REVIEW_COMMAND=bash scripts/ralph-selfhost-technical-review.sh

# Expressões PHP literais dentro de aspas simples: sem expansão shell.
# shellcheck disable=SC2016

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"
FEATURE="${RALPH_FEATURE_KEY:-}"
ENGINE="${RALPH_ENGINE:-opencode}"

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ]; then
  echo "contexto ausente: RALPH_WORKFLOW_ID e RALPH_FEATURE_KEY são obrigatórios" >&2
  exit 2
fi

# Descobre o input_file da feature no workflow ativo do runtime.
WORKFLOW_FILE="$REPO/.git/ralph-control/workflow.json"
INPUT=""
if [ -f "$WORKFLOW_FILE" ]; then
  INPUT="$(php -r '
    $w = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
    $feature = $argv[2];
    foreach ($w["features"] ?? [] as $f) {
        if (($f["feature_key"] ?? null) === $feature) {
            echo $f["input_file"] ?? "";
            exit(0);
        }
    }
    echo "";
  ' "$WORKFLOW_FILE" "$FEATURE" 2>/dev/null)"
fi
if [ -z "$INPUT" ]; then
  INPUT="$(php -r '
    $w = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
    echo $w["plan_file"] ?? "";
  ' "$WORKFLOW_FILE" 2>/dev/null)"
fi
if [ -z "$INPUT" ] || [ ! -f "$REPO/$INPUT" ]; then
  echo "input da feature não encontrado para revisão técnica" >&2
  exit 1
fi

# A revisão é read-only por construção: ralph.sh --verify-only usa o agente
# ralph-review com política de leitura (proof externa exigida pelo perfil).
cd "$REPO" || exit 2
bash scripts/ralph.sh --engine "$ENGINE" --verify-only "$INPUT" 2>&1
exit $?

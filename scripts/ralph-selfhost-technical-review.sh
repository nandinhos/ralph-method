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
# A revisão avalia SOMENTE a phase da feature atual (source_phase), não o
# PHASES.md inteiro: as phases futuras da fila ainda não existem no código e
# reprovar por elas seria um falso negativo. Usamos o manifest cortado por
# phase que o controlador já gerou no runtime (manifests/*.md).
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
ATTEMPT="${RALPH_ATTEMPT:-}"

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ]; then
  echo "contexto ausente: RALPH_WORKFLOW_ID e RALPH_FEATURE_KEY são obrigatórios" >&2
  exit 2
fi

# 1) Preferência: manifest cortado por phase já gerado pelo controlador no
#    runtime (o mesmo que o bloco usou). Ele contém somente a phase da
#    feature atual.
INPUT=""
MANIFEST_DIR="$REPO/.git/ralph-control/manifests"
if [ -d "$MANIFEST_DIR" ]; then
  if [ -n "$ATTEMPT" ]; then
    CANDIDATE="$MANIFEST_DIR/$(printf '%s' "$FEATURE" | sed 's/[^A-Za-z0-9._-]/_/g')-attempt-${ATTEMPT}.md"
    [ -f "$CANDIDATE" ] && INPUT="$CANDIDATE"
  fi
  if [ -z "$INPUT" ]; then
    # Fallback: o manifest mais recente da feature.
    INPUT="$(ls -t "$MANIFEST_DIR"/$(printf '%s' "$FEATURE" | sed 's/[^A-Za-z0-9._-]/_/g')-attempt-*.md 2>/dev/null | head -1 || true)"
  fi
fi

# 2) Fallback: corta o PHASES.md pela source_phase da feature (mesma lógica
#    do singleFeatureInput do controlador).
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  WORKFLOW_FILE="$REPO/.git/ralph-control/workflow.json"
  INPUT="$(php -r '
    $w = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
    $feature = $argv[2];
    $source = null;
    foreach ($w["features"] ?? [] as $f) {
        if (($f["feature_key"] ?? null) === $feature) {
            $source = $f["input_file"] ?? null;
            $phase = $f["source_phase"] ?? null;
            break;
        }
    }
    $source = $source ?? ($w["plan_file"] ?? null);
    if (! is_string($source) || $source === "" || $phase === null) { exit(1); }
    $path = $argv[3]."/".ltrim($source, "/");
    if (! is_file($path)) { exit(1); }
    $content = file_get_contents($path);
    $re = "/^## Phase ".preg_quote($phase, "/").":.*$/m";
    if (preg_match($re, $content, $m, PREG_OFFSET_CAPTURE) !== 1) { exit(1); }
    $start = $m[0][1];
    $rest = substr($content, $start + strlen($m[0][0]));
    $end = strlen($rest);
    if (preg_match("/^## Phase .*$/m", $rest, $next, PREG_OFFSET_CAPTURE) === 1) { $end = $next[0][1]; }
    echo $m[0][0].substr($rest, 0, $end);
    exit(0);
  ' "$WORKFLOW_FILE" "$FEATURE" "$REPO" 2>/dev/null)"
  if [ -n "$INPUT" ] && [ -n "$REPO" ]; then
    TMP_INPUT="$MANIFEST_DIR/$(printf '%s' "$FEATURE" | sed 's/[^A-Za-z0-9._-]/_/g')-attempt-${ATTEMPT:-0}-review.md"
    mkdir -p "$MANIFEST_DIR" 2>/dev/null || true
    printf '%s\n' "$INPUT" > "$TMP_INPUT"
    INPUT="$TMP_INPUT"
  fi
fi

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "input da feature não encontrado para revisão técnica" >&2
  exit 1
fi

# A revisão é read-only por construção: ralph.sh --verify-only usa o agente
# ralph-review com política de leitura (proof externa exigida pelo perfil).
cd "$REPO" || exit 2
bash scripts/ralph.sh --engine "$ENGINE" --verify-only "$INPUT" 2>&1
exit $?

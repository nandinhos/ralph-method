#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parser.php"

usage() {
  printf '%s\n' \
    'uso: runner.sh preflight [--mode impl|verify] [--repo-root DIR] [--model ID]' \
    '     runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \' \
    '       --result-file FILE --mode impl|verify --execution-id ID \' \
    '       --workflow-id ID --feature-key KEY --attempt N' \
    '     runner.sh version'
}

die() {
  printf 'ralph-cursor: %s\n' "$1" >&2
  exit 2
}

# Cursor é IDE com LLM embutido: a CLI pode ser `agent`, `cursor-agent` ou um
# bridge do harness do editor apontado por RALPH_CURSOR_CLI (caminho absoluto
# ou comando no PATH). O harness do editor (cursor-ralph-profile) é o
# consumidor canônico; não existe CLI headless obrigatória.
cursor_cli() {
  if [ -n "${RALPH_CURSOR_CLI:-}" ]; then
    printf '%s' "$RALPH_CURSOR_CLI"
    return
  fi
  if command -v cursor-agent >/dev/null 2>&1; then
    printf 'cursor-agent'
  else
    printf 'agent'
  fi
}

cursor_cli_available() {
  local cli
  cli="$(cursor_cli)"
  if [[ "$cli" == */* ]]; then
    [ -x "$cli" ]
  else
    command -v "$cli" >/dev/null 2>&1
  fi
}

version() {
  local cli output
  cli="$(cursor_cli)"
  output="$("$cli" --version 2>&1)" || die 'não foi possível obter a versão do Cursor'
  output="${output%%$'\n'*}"
  output="$(printf '%s' "$output" | tr -d '\r' | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')"
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'versão do Cursor não reconhecida'
  printf '%s\n' "$output"
}

selected_model() {
  printf '%s' "${RALPH_CURSOR_MODEL:-}"
}

preflight() {
  local mode='impl' repo_root='' model=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      *) die "opção desconhecida no preflight: $1" ;;
    esac
  done

  if ! cursor_cli_available; then
    die 'CLI do Cursor não encontrada (defina RALPH_CURSOR_CLI ou instale agent/cursor-agent)'
  fi
  command -v php >/dev/null 2>&1 || die 'PHP não encontrado'
  [ -f "$PARSER" ] || die 'parser cursor ausente'
  [[ "$mode" == impl || "$mode" == verify ]] || die "modo inválido: $mode"
  [ -n "$model" ] || model="$(selected_model)"
  [ -n "$model" ] || die 'RALPH_CURSOR_MODEL deve ser explícito'
  [[ "$model" =~ ^[^[:space:]]+$ ]] || die "modelo inválido: $model"
  [ "$mode" = verify ] && [ -n "$repo_root" ] || { [ "$mode" = impl ] || die 'verify exige repo-root explícito'; }

  # verify v1 é declarado (ask), nunca verified.
  local policy_status='not_required'
  [ "$mode" = verify ] && policy_status='declared'
  printf '{"status":"ready","runner":"cursor","runner_version":"%s","requested_model":"%s","prompt_transport":"file","permission_policy_status":"%s","permission_policy_hash":null}\n' \
    "$(version)" "$model" "$policy_status"
}

run_engine() {
  local repo_root='' prompt_file='' events_file='' result_file='' mode='impl'
  local execution_id='' workflow_id="${RALPH_EXECUTION_WORKFLOW_ID:-}"
  local feature_key="${RALPH_EXECUTION_FEATURE_KEY:-}" attempt="${RALPH_EXECUTION_ATTEMPT:-}"
  local model='' max_prompt_bytes="${RALPH_CURSOR_MAX_PROMPT_BYTES:-262144}"
  local max_event_bytes="${RALPH_CURSOR_MAX_EVENT_BYTES:-5242880}"
  local max_events="${RALPH_CURSOR_MAX_EVENTS:-10000}"
  local timeout_seconds="${RALPH_CURSOR_TIMEOUT:-1800}"
  local verify_mode="${RALPH_CURSOR_VERIFY_MODE:-ask}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --prompt-file) prompt_file="${2:-}"; shift 2 ;;
      --events-file) events_file="${2:-}"; shift 2 ;;
      --result-file) result_file="${2:-}"; shift 2 ;;
      --mode) mode="${2:-}"; shift 2 ;;
      --execution-id) execution_id="${2:-}"; shift 2 ;;
      --workflow-id) workflow_id="${2:-}"; shift 2 ;;
      --feature-key) feature_key="${2:-}"; shift 2 ;;
      --attempt) attempt="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      *) die "opção desconhecida na execução: $1" ;;
    esac
  done

  repo_root="$(cd "$repo_root" 2>/dev/null && pwd -P)" || die 'repo-root inválido'
  [ -f "$prompt_file" ] || die "prompt ausente: $prompt_file"
  [ -n "$events_file" ] || die 'events-file obrigatório'
  [ -n "$result_file" ] || die 'result-file obrigatório'
  [[ "$mode" == impl || "$mode" == verify ]] || die "modo inválido: $mode"
  [[ "$execution_id" =~ ^exec_[A-Za-z0-9_-]+$ ]] || die 'execution-id inválido'
  [[ "$workflow_id" =~ ^wf_[A-Za-z0-9_-]+$ ]] || die 'workflow-id inválido'
  [[ "$feature_key" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || die 'feature-key inválida'
  [[ "$attempt" =~ ^[0-9]+$ ]] || die 'attempt inválida'
  [ -n "$model" ] || model="$(selected_model)"
  [ -n "$model" ] || die 'RALPH_CURSOR_MODEL deve ser explícito'
  [[ "$max_prompt_bytes" =~ ^[1-9][0-9]*$ && "$max_event_bytes" =~ ^[1-9][0-9]*$ && "$max_events" =~ ^[1-9][0-9]*$ ]] || die 'limites inválidos'
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die 'timeout inválido'
  [ "$verify_mode" = ask ] || die "RALPH_CURSOR_VERIFY_MODE inválido (v1 só ask)"

  local prompt_bytes prompt
  prompt_bytes="$(wc -c < "$prompt_file")"
  [ "$prompt_bytes" -le "$max_prompt_bytes" ] || die "prompt excede ${max_prompt_bytes} bytes"
  prompt="$(<"$prompt_file")"
  mkdir -p "$(dirname "$events_file")" "$(dirname "$result_file")"
  local raw_events="$events_file.raw" text_output="${result_file}.text"
  local runner_version prompt_sha256
  runner_version="$(version)"
  prompt_sha256="$(php -r 'echo hash_file("sha256", $argv[1]);' "$prompt_file")"

  local policy_status='not_required' verification_agent=''
  local command=( "$(cursor_cli)" -p )
  if [ "$mode" = verify ]; then
    verification_agent='ask'
    policy_status='declared'
    command+=(--mode ask --trust)
  else
    command+=(--force --trust)
  fi
  command+=(--output-format stream-json --workspace "$repo_root" --model "$model")
  command+=("$prompt")

  local rc=0
  (cd "$repo_root" && timeout --kill-after=10s "${timeout_seconds}s" "${command[@]}") > "$raw_events" 2> "${events_file}.stderr" || rc=$?

  php "$PARSER" \
    --events "$raw_events" --sanitized-events "$events_file" --result "$result_file" \
    --repo-root "$repo_root" --exit-code "$rc" --runner-version "$runner_version" \
    --requested-model "$model" --execution-id "$execution_id" --execution-mode "$mode" \
    --workflow-id "$workflow_id" --feature-key "$feature_key" --attempt "$attempt" \
    --prompt-sha256 "$prompt_sha256" --prompt-transport file \
    --permission-policy-status "$policy_status" --permission-policy-hash none \
    --verification-agent "${verification_agent:-none}" --text-output "$text_output" \
    --max-event-bytes "$max_event_bytes" --max-events "$max_events"
  rm -f "$raw_events" "${events_file}.stderr"

  cat "$result_file"
  [ ! -s "$text_output" ] || cat "$text_output"
  local status
  status="$(php -r '$v=json_decode(file_get_contents($argv[1]), true); echo is_array($v) ? ($v["status"] ?? "failed") : "failed";' "$result_file")"
  [ "$status" = completed ]
}

command="${1:-}"
[ -n "$command" ] || { usage >&2; exit 2; }
shift
case "$command" in
  preflight) preflight "$@" ;;
  run) run_engine "$@" ;;
  version) version ;;
  *) usage >&2; exit 2 ;;
esac
